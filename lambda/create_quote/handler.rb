require 'json'
require_relative '../shared/db_client'

# Lambda handler for creating a new quote
# POST /quotes
def lambda_handler(event:, context:)
  puts "Event: #{JSON.generate(event)}"

  # Parse request body
  body = JSON.parse(event['body'] || '{}')
  
  # Validate required top-level fields
  ValidationHelper.validate_required_fields(body, ['userId', 'customerName', 'customerPhone', 'customerAddress'])
  
  # Validate items array
  ValidationHelper.validate_items(body['items'])
  
  # Generate quote ID and timestamps
  quote_id = DbClient.generate_ulid
  timestamp = DbClient.current_timestamp
  
  # Process items - generate itemIds for each
  items = body['items'].map do |item_data|
    ValidationHelper.validate_item(item_data)
    ItemHelper.build_item(item_data)
  end
  
  # Calculate total price from items
  total_price = ItemHelper.calculate_total_price(items)
  
  # Validate status if provided
  status = body['status'] || 'draft'
  ValidationHelper.validate_quote_status(status)
  
  # Build quote object
  quote = {
    'quoteId' => quote_id,
    'userId' => body['userId'],
    'customerName' => body['customerName'],
    'customerPhone' => body['customerPhone'],
    'customerAddress' => body['customerAddress'],
    'status' => status,
    'items' => items,
    'totalPrice' => total_price,
    'notes' => body['notes'] || '',
    'createdAt' => timestamp,
    'updatedAt' => timestamp
  }
  
  # Save to DynamoDB
  quotes_table = ENV['QUOTES_TABLE_NAME']
  DbClient.put_item(quotes_table, quote)
  
  puts "Created quote: #{quote_id} with #{items.length} items, total: $#{total_price / 100.0}"
  
  # Return success response
  ResponseHelper.success(201, quote)
  
rescue ValidationHelper::ValidationError => e
  puts "Validation error: #{e.message}"
  ResponseHelper.error(400, 'ValidationError', e.message)
rescue JSON::ParserError => e
  puts "JSON parse error: #{e.message}"
  ResponseHelper.error(400, 'InvalidJSON', 'Request body must be valid JSON')
rescue DbClient::DbError => e
  puts "Database error: #{e.message}"
  ResponseHelper.error(500, 'DatabaseError', 'Failed to create quote')
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
  puts e.backtrace
  ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
end
