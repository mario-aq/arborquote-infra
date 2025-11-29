require 'json'
require_relative '../shared/db_client'

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
  
  # Return quotes sorted by createdAt (descending - most recent first)
  sorted_quotes = quotes.sort_by { |q| q['createdAt'] }.reverse
  
  ResponseHelper.success(200, {
    quotes: sorted_quotes,
    count: sorted_quotes.length,
    userId: user_id
  })
  
rescue DbClient::DbError => e
  puts "Database error: #{e.message}"
  ResponseHelper.error(500, 'DatabaseError', 'Failed to retrieve quotes')
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
  puts e.backtrace
  ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
end

