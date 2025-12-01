require 'json'
require_relative '../shared/db_client'
require_relative '../shared/pdf_client'
require_relative 'pdf_generator'

# Lambda handler for generating quote PDFs
# POST /quotes/{quoteId}/pdf
# Implements hash-based caching to avoid regenerating unchanged PDFs
def lambda_handler(event:, context:)
  puts "Event: #{event.inspect}"
  
  # Parse request
  quote_id = event.dig('pathParameters', 'quoteId')
  body = event['body'] ? JSON.parse(event['body']) : {}
  user_id = body['userId']
  locale = body['locale'] || 'en'
  force_regenerate = body['forceRegenerate'] || false
  
  # Validate inputs
  unless quote_id
    return error_response(400, 'ValidationError', 'Missing quoteId in path')
  end
  
  unless user_id
    return error_response(400, 'ValidationError', 'Missing userId in request body')
  end
  
  unless ['en', 'es'].include?(locale)
    return error_response(400, 'ValidationError', "Invalid locale. Must be 'en' or 'es'")
  end
  
  # Get environment variables
  quotes_table = ENV['QUOTES_TABLE_NAME']
  pdf_bucket = ENV['PDF_BUCKET_NAME']
  
  unless quotes_table && pdf_bucket
    return error_response(500, 'ConfigurationError', 'Missing environment configuration')
  end
  
  begin
    # 1. Fetch quote from DynamoDB
    puts "Fetching quote #{quote_id} from DynamoDB..."
    quote = DbClient.get_item(quotes_table, { 'quoteId' => quote_id })
    
    unless quote
      return error_response(404, 'QuoteNotFound', "Quote with ID #{quote_id} not found")
    end
    
    # Verify quote belongs to user (basic ownership check)
    if quote['userId'] != user_id
      return error_response(403, 'Forbidden', 'Quote does not belong to this user')
    end
    
    # 2. Compute content hash
    puts "Computing content hash for quote..."
    new_hash = PdfClient.compute_quote_content_hash(quote)
    puts "New hash: #{new_hash}"
    
    # 3. Check cache for this specific locale (skip if force regenerate)
    # Store locale-specific PDF keys: pdfS3Key_en, pdfS3Key_es
    pdf_key_field = locale == 'es' ? 'pdfS3KeyEs' : 'pdfS3KeyEn'
    existing_pdf_key = quote[pdf_key_field]
    existing_hash = quote['lastPdfHash']
    
    if !force_regenerate && existing_pdf_key && existing_hash
      puts "Found existing PDF for locale #{locale}: key=#{existing_pdf_key}, hash=#{existing_hash}"
      
      if new_hash == existing_hash
        puts "Hash matches! Checking if #{locale} PDF exists in S3..."
        
        # Verify PDF still exists in S3
        if PdfClient.pdf_exists?(pdf_bucket, existing_pdf_key)
          # Generate new presigned URL for existing PDF
          pdf_url = PdfClient.generate_pdf_presigned_url(pdf_bucket, existing_pdf_key)
          
          return success_response({
            quoteId: quote_id,
            pdfUrl: pdf_url,
            ttlSeconds: 604800,
            cached: true
          })
        else
          puts "Warning: PDF metadata exists but file not found in S3. Regenerating..."
        end
      else
        puts "Hash changed (old: #{existing_hash}, new: #{new_hash}). Regenerating PDF..."
      end
    else
      puts "No cached PDF for locale #{locale} or force regenerate requested. Generating new PDF..."
    end
    
    # 4. Generate PDF
    puts "Generating PDF in #{locale}..."
    pdf_data = if locale == 'es'
                 PdfGenerator.generate_pdf_es(quote)
               else
                 PdfGenerator.generate_pdf_en(quote)
               end
    
    # 5. Upload to S3 with locale-specific key
    s3_key = PdfClient.generate_pdf_key(user_id, quote_id, locale)
    puts "Uploading PDF to S3: #{s3_key}"
    PdfClient.upload_pdf(pdf_bucket, s3_key, pdf_data)
    
    # 6. Update DynamoDB with locale-specific PDF metadata
    puts "Updating quote with PDF metadata for locale #{locale}..."
    updates = {
      pdf_key_field => s3_key,
      'lastPdfHash' => new_hash
    }
    DbClient.update_item(
      quotes_table,
      { 'quoteId' => quote_id },
      updates
    )
    
    # 7. Generate presigned URL
    pdf_url = PdfClient.generate_pdf_presigned_url(pdf_bucket, s3_key)
    
    puts "PDF generated successfully!"
    success_response({
      quoteId: quote_id,
      pdfUrl: pdf_url,
      ttlSeconds: 604800,
      cached: false
    })
    
  rescue DbClient::DbError => e
    puts "Database error: #{e.message}"
    error_response(500, 'DatabaseError', e.message)
  rescue StandardError => e
    puts "Error generating PDF: #{e.message}"
    puts e.backtrace.join("\n")
    error_response(500, 'InternalServerError', 'An unexpected error occurred while generating PDF')
  end
end

# Success response helper
def success_response(data)
  {
    statusCode: 200,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: JSON.generate(data)
  }
end

# Error response helper
def error_response(status_code, error_type, message)
  {
    statusCode: status_code,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: JSON.generate({
      error: error_type,
      message: message
    })
  }
end

