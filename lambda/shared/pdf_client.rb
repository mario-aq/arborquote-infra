require 'aws-sdk-s3'
require 'json'
require 'digest'

# Shared PDF utilities for Lambda handlers
module PdfClient
  class << self
    # Lazy-load S3 client
    def s3_client
      @s3_client ||= Aws::S3::Client.new
    end

    # Compute SHA-256 hash of quote content for caching
    # Returns consistent hash for same content, ignoring timestamps and status
    def compute_quote_content_hash(quote)
      # Create canonical payload that includes all content-affecting fields
      # Note: We exclude 'status' since it doesn't affect the PDF content
      # (draft/sent/accepted doesn't change what's shown in the PDF)
      canonical_data = {
        quoteId: quote['quoteId'],
        customerName: quote['customerName'],
        customerPhone: quote['customerPhone'],
        customerAddress: quote['customerAddress'],
        notes: quote['notes'],
        # Sort items by itemId for consistency
        items: (quote['items'] || []).sort_by { |item| item['itemId'] || '' }.map do |item|
          {
            itemId: item['itemId'],
            type: item['type'],
            description: item['description'],
            diameterInInches: item['diameterInInches'],
            heightInFeet: item['heightInFeet'],
            riskFactors: item['riskFactors'],
            price: item['price']
            # Note: We exclude 'photos' array from hash since photos are visual
            # and don't affect the text content of the quote
          }
        end,
        totalPrice: quote['totalPrice']
      }

      # Convert to JSON string (sorted keys for consistency)
      json_string = JSON.generate(canonical_data, object_nl: '', array_nl: '', indent: '')
      
      # Compute SHA-256 hash
      Digest::SHA256.hexdigest(json_string)
    end

    # Generate S3 key for PDF
    # Format: userId/quoteId/arbor_quote_{quoteId}_{locale}.pdf
    def generate_pdf_key(user_id, quote_id, locale = 'en')
      "#{user_id}/#{quote_id}/arbor_quote_#{quote_id}_#{locale}.pdf"
    end

    # Generate presigned URL for PDF download
    # Default TTL: 7 days (604800 seconds)
    def generate_pdf_presigned_url(bucket_name, s3_key, ttl = 604800)
      presigner = Aws::S3::Presigner.new(client: s3_client)
      presigner.presigned_url(
        :get_object,
        bucket: bucket_name,
        key: s3_key,
        expires_in: ttl
      )
    end

    # Upload PDF to S3
    def upload_pdf(bucket_name, s3_key, pdf_data)
      s3_client.put_object(
        bucket: bucket_name,
        key: s3_key,
        body: pdf_data,
        content_type: 'application/pdf',
        content_disposition: 'inline' # Allow viewing in browser
      )
    rescue Aws::S3::Errors::ServiceError => e
      raise "Failed to upload PDF to S3: #{e.message}"
    end

    # Delete PDF from S3
    def delete_pdf(bucket_name, s3_key)
      s3_client.delete_object(
        bucket: bucket_name,
        key: s3_key
      )
    rescue Aws::S3::Errors::ServiceError => e
      # Log but don't fail - best effort cleanup
      puts "Warning: Failed to delete PDF from S3: #{e.message}"
    end

    # Check if PDF exists in S3
    def pdf_exists?(bucket_name, s3_key)
      s3_client.head_object(
        bucket: bucket_name,
        key: s3_key
      )
      true
    rescue Aws::S3::Errors::NotFound
      false
    rescue Aws::S3::Errors::ServiceError => e
      puts "Warning: Failed to check PDF existence: #{e.message}"
      false
    end
  end
end

