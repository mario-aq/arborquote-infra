require 'json'
require_relative '../shared/db_client'

# Lambda handler for updating an existing quote
# PUT /quotes/{quoteId}
def lambda_handler(event:, context:)
  puts "Event: #{JSON.generate(event)}"

  # Get quoteId from path parameters
  path_params = event['pathParameters'] || {}
  quote_id = path_params['quoteId']
  
  if quote_id.nil? || quote_id.strip.empty?
    return ResponseHelper.error(400, 'ValidationError', 'quoteId path parameter is required')
  end
  
  # Parse request body
  body = JSON.parse(event['body'] || '{}')
  
  if body.empty?
    return ResponseHelper.error(400, 'ValidationError', 'Request body cannot be empty')
  end
  
  # Check if quote exists first
  quotes_table = ENV['QUOTES_TABLE_NAME']
  existing_quote = DbClient.get_item(
    quotes_table,
    { 'quoteId' => quote_id }
  )
  
  if existing_quote.nil?
    puts "Quote not found: #{quote_id}"
    return ResponseHelper.error(404, 'QuoteNotFound', "Quote with ID #{quote_id} not found")
  end
  
  # Build updates hash (only update fields provided in request)
  updates = {}
  updatable_fields = ['customerName', 'customerPhone', 'customerAddress', 'notes', 'status']
  
  updatable_fields.each do |field|
    updates[field] = body[field] if body.key?(field)
  end
  
  # Handle items update specially
  if body.key?('items')
    # Validate new items
    ValidationHelper.validate_items(body['items'])
    
    # Process items - generate itemIds if not provided
    items = body['items'].map do |item_data|
      # If itemId exists, preserve it (editing existing item)
      # Otherwise generate new one (new item)
      if item_data['itemId']
        item_data
      else
        ValidationHelper.validate_item(item_data)
        ItemHelper.build_item(item_data)
      end
    end
    
    # Recalculate total price
    total_price = ItemHelper.calculate_total_price(items)
    
    updates['items'] = items
    updates['totalPrice'] = total_price
    
    puts "Updated items: #{items.length} items, new total: $#{total_price / 100.0}"
  end
  
  # Validate status if being updated
  if updates['status']
    ValidationHelper.validate_quote_status(updates['status'])
  end
  
  # Always update the updatedAt timestamp
  updates['updatedAt'] = DbClient.current_timestamp
  
  # Update item in DynamoDB
  updated_quote = DbClient.update_item(
    quotes_table,
    { 'quoteId' => quote_id },
    updates
  )
  
  puts "Updated quote: #{quote_id}"
  
  ResponseHelper.success(200, updated_quote)
  
rescue ValidationHelper::ValidationError => e
  puts "Validation error: #{e.message}"
  ResponseHelper.error(400, 'ValidationError', e.message)
rescue JSON::ParserError => e
  puts "JSON parse error: #{e.message}"
  ResponseHelper.error(400, 'InvalidJSON', 'Request body must be valid JSON')
rescue DbClient::DbError => e
  puts "Database error: #{e.message}"
  ResponseHelper.error(500, 'DatabaseError', 'Failed to update quote')
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
  puts e.backtrace
  ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
end
