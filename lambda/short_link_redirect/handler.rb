require 'json'
require_relative '../shared/auth_helper'
require_relative '../shared/db_client'
require_relative '../shared/pdf_client'

# Lambda handler for short link redirects
# GET /q/{slug}
# Returns 302 redirect to presigned S3 URL with lazy regeneration
def lambda_handler(event:, context:)
  begin
    # Extract authenticated user from JWT
    user = AuthHelper.extract_user_from_jwt(event)
  # Extract slug from path parameters
  slug = event.dig('pathParameters', 'slug')

  # Validate request size
  ValidationHelper.validate_request_size(event)
  
  # Validate slug
  unless slug && slug.match?(/^[a-z0-9]{8}$/)
    return error_response(400, 'ValidationError', 'Invalid or missing slug')
  end
  
  # Get environment variables
  short_links_table = ENV['SHORT_LINKS_TABLE_NAME']
  pdf_bucket = ENV['PDF_BUCKET_NAME']
  presigned_ttl = (ENV['PRESIGNED_TTL_SECONDS'] || '3600').to_i # Default 1 hour (short links auto-refresh)
  
  unless short_links_table && pdf_bucket
    return error_response(500, 'ConfigurationError', 'Missing environment configuration')
  end
  
  begin
    # 1. Lookup short link in DynamoDB
    puts "Looking up short link: #{slug}"
    short_link = DbClient.get_item(short_links_table, { 'slug' => slug })
    
    unless short_link
      puts "Short link not found: #{slug}"
      return error_response(404, 'ShortLinkNotFound', 'Short link not found')
    end
    
    puts "Found short link: quoteId=#{short_link['quoteId']}, locale=#{short_link['locale']}"
    
    pdf_key = short_link['pdfKey']
    last_presigned_url = short_link['lastPresignedUrl']
    last_expires_at = short_link['lastPresignedExpiresAt']
    
    # 2. Check if cached presigned URL is still valid
    # Conservative buffer: require >60 seconds remaining to avoid edge cases
    # (presigned URLs can expire early if Lambda credentials expire)
    now = Time.now.to_i
    url_still_valid = last_presigned_url && 
                      last_expires_at && 
                      last_expires_at.to_i > (now + 60)
    
    if url_still_valid
      # Use cached presigned URL
      puts "Using cached presigned URL (expires at: #{Time.at(last_expires_at.to_i).utc})"
      return redirect_response(last_presigned_url)
    end
    
    # 3. Generate new presigned URL
    puts "Generating new presigned URL for: #{pdf_key}"
    new_presigned_url = PdfClient.generate_pdf_presigned_url(
      pdf_bucket,
      pdf_key,
      presigned_ttl
    )
    # Be conservative: assume URL expires 5 minutes before the nominal TTL
    # to account for credential expiration (presigned URLs expire when credentials expire)
    new_expires_at = now + presigned_ttl - 300
    
    # 4. Update DynamoDB with new presigned URL
    puts "Updating short link with new presigned URL (expires: #{Time.at(new_expires_at).utc})"
    DbClient.update_item(
      short_links_table,
      { 'slug' => slug },
      {
        'lastPresignedUrl' => new_presigned_url,
        'lastPresignedExpiresAt' => new_expires_at,
        'updatedAt' => DbClient.current_timestamp
      }
    )
    
    # 5. Redirect to new presigned URL
    puts "Redirecting to new presigned URL"
    redirect_response(new_presigned_url)
    
  rescue DbClient::DbError => e
    puts "Database error: #{e.message}"
    error_response(500, 'DatabaseError', 'Failed to lookup short link')
  rescue StandardError => e
    puts "Error processing short link redirect: #{e.message}"
    puts e.backtrace.join("\n")
    error_response(500, 'InternalServerError', 'An unexpected error occurred')
  end
end

# 302 redirect response
def redirect_response(location)
  {
    statusCode: 302,
    headers: {
      'Location' => location,
      'Cache-Control' => 'no-cache', # Don't cache redirects
      'Access-Control-Allow-Origin' => '*'
    },
    body: ''
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

