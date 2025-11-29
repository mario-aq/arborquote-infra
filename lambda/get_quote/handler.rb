require 'json'
require_relative '../shared/db_client'
require_relative '../shared/s3_client'

# Lambda handler for getting a single quote by ID
# GET /quotes/{quoteId}
def lambda_handler(event:, context:)
  puts "Event: #{JSON.generate(event)}"

  # Get quoteId from path parameters
  path_params = event['pathParameters'] || {}
  quote_id = path_params['quoteId']
  
  if quote_id.nil? || quote_id.strip.empty?
    return ResponseHelper.error(400, 'ValidationError', 'quoteId path parameter is required')
  end
  
  # Get quote from DynamoDB
  quotes_table = ENV['QUOTES_TABLE_NAME']
  
  quote = DbClient.get_item(
    quotes_table,
    { 'quoteId' => quote_id }
  )
  
  if quote.nil?
    puts "Quote not found: #{quote_id}"
    return ResponseHelper.error(404, 'QuoteNotFound', "Quote with ID #{quote_id} not found")
  end
  
  # Generate presigned URLs for photos
  bucket_name = ENV['PHOTOS_BUCKET_NAME']
  quote_with_presigned = generate_presigned_urls_for_quote(quote, bucket_name)
  
  puts "Retrieved quote: #{quote_id}"
  
  ResponseHelper.success(200, quote_with_presigned)
  
rescue DbClient::DbError => e
  puts "Database error: #{e.message}"
  ResponseHelper.error(500, 'DatabaseError', 'Failed to retrieve quote')
rescue S3Client::S3Error => e
  puts "S3 error: #{e.message}"
  ResponseHelper.error(500, 'S3Error', 'Failed to generate photo URLs')
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
  puts e.backtrace
  ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
end

# Helper function to generate presigned URLs for all photos in a quote
def generate_presigned_urls_for_quote(quote, bucket_name)
  quote_copy = quote.dup
  
  if quote_copy['items'] && !quote_copy['items'].empty?
    quote_copy['items'] = quote_copy['items'].map do |item|
      item_copy = item.dup
      
      if item_copy['photos'] && !item_copy['photos'].empty?
        item_copy['photos'] = item_copy['photos'].map do |s3_key|
          # Generate presigned URL (expires in 1 hour)
          S3Client.generate_presigned_url(bucket_name, s3_key, expires_in: 3600)
        end
      end
      
      item_copy
    end
  end
  
  quote_copy
end

