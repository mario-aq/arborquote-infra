require 'json'
require_relative '../shared/db_client'

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
  
  puts "Retrieved quote: #{quote_id}"
  
  ResponseHelper.success(200, quote)
  
rescue DbClient::DbError => e
  puts "Database error: #{e.message}"
  ResponseHelper.error(500, 'DatabaseError', 'Failed to retrieve quote')
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
  puts e.backtrace
  ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
end

