require 'json'
require_relative '../shared/db_client'
require_relative '../shared/s3_client'

# Lambda handler for listing quotes by userId
# GET /quotes?userId=xxx
def lambda_handler(event:, context:)
  puts "Event: #{JSON.generate(event)}"

  # Get userId from query parameters
  query_params = event['queryStringParameters'] || {}
  user_id = query_params['userId']
  
  if user_id.nil? || user_id.strip.empty?
    return ResponseHelper.error(400, 'ValidationError', 'userId query parameter is required')
  end
  
  # Query DynamoDB using GSI
  quotes_table = ENV['QUOTES_TABLE_NAME']
  
  quotes = DbClient.query(
    quotes_table,
    index_name: 'userId-index',
    key_condition_expression: '#userId = :userId',
    expression_attribute_names: {
      '#userId' => 'userId'
    },
    expression_attribute_values: {
      ':userId' => user_id
    }
  )
  
  puts "Found #{quotes.length} quotes for user: #{user_id}"
  
  # Generate presigned URLs for photos in all quotes
  bucket_name = ENV['PHOTOS_BUCKET_NAME']
  quotes_with_presigned = quotes.map { |quote| generate_presigned_urls_for_quote(quote, bucket_name) }
  
  # Return quotes sorted by createdAt (descending - most recent first)
  sorted_quotes = quotes_with_presigned.sort_by { |q| q['createdAt'] }.reverse
  
  ResponseHelper.success(200, {
    quotes: sorted_quotes,
    count: sorted_quotes.length,
    userId: user_id
  })
  
rescue DbClient::DbError => e
  puts "Database error: #{e.message}"
  ResponseHelper.error(500, 'DatabaseError', 'Failed to retrieve quotes')
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

