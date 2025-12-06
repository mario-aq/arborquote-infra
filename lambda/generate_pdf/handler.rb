require 'json'
require_relative '../shared/db_client'
require_relative '../shared/pdf_client'
require_relative '../shared/short_link_client'
require_relative 'pdf_generator'

# Lambda handler for generating quote PDFs
# POST /quotes/{quoteId}/pdf
# Implements hash-based caching to avoid regenerating unchanged PDFs
def lambda_handler(event:, context:)
  # Parse request
  quote_id = event.dig('pathParameters', 'quoteId')
  body = event['body'] ? JSON.parse(event['body']) : {}
  user_id = body['userId']
  locale = body['locale'] || 'en'
  force_regenerate = body['forceRegenerate'] || false

  # Validate request size
  ValidationHelper.validate_request_size(event)
  
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

  puts "Generating PDF for quote #{quote_id} in locale #{locale} (force: #{force_regenerate})"
  
  # Get environment variables
  quotes_table = ENV['QUOTES_TABLE_NAME']
  users_table = ENV['USERS_TABLE_NAME']
  companies_table = ENV['COMPANIES_TABLE_NAME']
  pdf_bucket = ENV['PDF_BUCKET_NAME']
  short_links_table = ENV['SHORT_LINKS_TABLE_NAME']
  
  unless quotes_table && pdf_bucket && users_table && companies_table
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
    
    # 2. Fetch user and company data for provider info
    puts "Fetching user #{user_id} from DynamoDB..."
    user = DbClient.get_item(users_table, { 'userId' => user_id })
    
    company = nil
    if user && user['companyId']
      puts "Fetching company #{user['companyId']} from DynamoDB..."
      company = DbClient.get_item(companies_table, { 'companyId' => user['companyId'] })
    end
    
    # 3. Compute content hash
    puts "Computing content hash for quote..."
    new_hash = PdfClient.compute_quote_content_hash(quote)
    puts "New hash: #{new_hash}"
    
    # 3. Check cache for this specific locale (skip if force regenerate)
    # Store locale-specific PDF keys: pdfS3Key_en, pdfS3Key_es
    # Store locale-specific hashes: lastPdfHashEn, lastPdfHashEs
    pdf_key_field = locale == 'es' ? 'pdfS3KeyEs' : 'pdfS3KeyEn'
    hash_field = locale == 'es' ? 'lastPdfHashEs' : 'lastPdfHashEn'
    existing_pdf_key = quote[pdf_key_field]
    existing_hash = quote[hash_field]
    
    if !force_regenerate && existing_pdf_key && existing_hash
      puts "Found existing PDF for locale #{locale}: key=#{existing_pdf_key}, hash=#{existing_hash}"
      
      if new_hash == existing_hash
        puts "Hash matches! Checking if #{locale} PDF exists in S3..."
        
        # Verify PDF still exists in S3
        if PdfClient.pdf_exists?(pdf_bucket, existing_pdf_key)
          # Generate new presigned URL for existing PDF
          pdf_url = PdfClient.generate_pdf_presigned_url(pdf_bucket, existing_pdf_key)
          
          # Ensure short link exists (create if missing)
          short_url = nil
          if short_links_table
            begin
              slug = ShortLinkClient.upsert_short_link(
                short_links_table,
                quote_id,
                locale,
                existing_pdf_key
              )
              short_url = "https://aquote.link/q/#{slug}"
              puts "Short link verified/created: #{short_url}"
            rescue StandardError => e
              puts "Warning: Failed to create short link: #{e.message}"
              # Non-fatal - continue with cached PDF
            end
          end
          
          response = {
            quoteId: quote_id,
            pdfUrl: pdf_url,
            ttlSeconds: 3600, # 1 hour (short links auto-refresh)
            cached: true
          }
          response[:shortUrl] = short_url if short_url
          
          return success_response(response)
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
                 PdfGenerator.generate_pdf_es(quote, user, company)
               else
                 PdfGenerator.generate_pdf_en(quote, user, company)
               end
    
    # 5. Upload to S3 with locale-specific key
    s3_key = PdfClient.generate_pdf_key(user_id, quote_id, locale)
    puts "Uploading PDF to S3: #{s3_key}"
    PdfClient.upload_pdf(pdf_bucket, s3_key, pdf_data)
    
    # 6. Create/update short link for this PDF
    slug = nil
    short_url = nil
    
    if short_links_table
      begin
        slug = ShortLinkClient.upsert_short_link(
          short_links_table,
          quote_id,
          locale,
          s3_key
        )
        short_url = "https://aquote.link/q/#{slug}"
        puts "Short link created: #{short_url}"
      rescue StandardError => e
        puts "Warning: Failed to create short link: #{e.message}"
        # Non-fatal - continue with PDF generation
      end
    else
      puts "Warning: SHORT_LINKS_TABLE_NAME not set, skipping short link creation"
    end
    
    # 7. Update DynamoDB with locale-specific PDF metadata
    puts "Updating quote with PDF metadata for locale #{locale}..."
    updates = {
      pdf_key_field => s3_key,
      hash_field => new_hash
    }
    DbClient.update_item(
      quotes_table,
      { 'quoteId' => quote_id },
      updates
    )
    
    # 8. Generate presigned URL
    pdf_url = PdfClient.generate_pdf_presigned_url(pdf_bucket, s3_key)
    
    puts "PDF generated successfully!"
    response = {
      quoteId: quote_id,
      pdfUrl: pdf_url,
      ttlSeconds: 3600, # 1 hour (short links auto-refresh)
      cached: false
    }
    
    # Add shortUrl to response if available
    response[:shortUrl] = short_url if short_url
    
    success_response(response)
    
  rescue DbClient::DbError => e
    puts "Database error: #{e.message}"
    error_response(500, 'DatabaseError', 'Failed to access database')
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

