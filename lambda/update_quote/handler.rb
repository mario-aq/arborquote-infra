require 'json'
require 'date'
require_relative '../shared/db_client'
require_relative '../shared/s3_client'

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
    # Validate new items (allow empty array for updates)
    ValidationHelper.validate_items(body['items'], allow_empty: true)
    
    bucket_name = ENV['PHOTOS_BUCKET_NAME']
    user_id = existing_quote['userId']
    created_at = existing_quote['createdAt']
    
    # Process photo deletions for removed items
    handle_photo_deletions(existing_quote['items'], body['items'], bucket_name, user_id, quote_id, created_at)
    
    # Process items - generate itemIds if not provided, handle photo uploads
    items = body['items'].map.with_index do |item_data, index|
      # If itemId exists, preserve it (editing existing item)
      # Otherwise generate new one (new item)
      item = if item_data['itemId']
               item_data.dup
             else
               ValidationHelper.validate_item(item_data)
               ItemHelper.build_item(item_data)
             end
      
      # Handle photo uploads if present
      if item_data['photos'] && !item_data['photos'].empty?
        # Check if photos are base64 data (new uploads) or S3 keys (existing)
        processed_photos = item_data['photos'].map.with_index do |photo, photo_idx|
          if photo.is_a?(Hash) && photo['data']
            # New photo - upload to S3
            filename = photo['filename'] || "photo-#{photo_idx + 1}"
            extension = S3Client.extension_from_content_type(photo['contentType'])
            filename_with_ext = filename.include?('.') ? filename : "#{filename}.#{extension}"
            
            # Use itemId instead of array index
            s3_key = S3Client.generate_photo_key(
              created_at,
              user_id,
              quote_id,
              item['itemId'],  # Use itemId instead of index
              filename_with_ext
            )
            
            S3Client.upload_photo_base64(
              bucket_name,
              s3_key,
              photo['data'],
              photo['contentType']
            )
            
            s3_key
          else
            # Existing photo - keep S3 key as is
            photo
          end
        end
        
        item['photos'] = processed_photos
      end
      
      item
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
rescue S3Client::S3Error => e
  puts "S3 error: #{e.message}"
  ResponseHelper.error(500, 'S3Error', "Failed to manage photos: #{e.message}")
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

# Helper function to handle photo deletions when items are removed
def handle_photo_deletions(existing_items, new_items, bucket_name, user_id, quote_id, created_at)
  return if existing_items.nil? || existing_items.empty?
  
  # Find items that were removed (exist in old but not in new)
  existing_item_ids = existing_items.map { |item| item['itemId'] }.compact
  new_item_ids = new_items.map { |item| item['itemId'] }.compact
  removed_item_ids = existing_item_ids - new_item_ids
  
  return if removed_item_ids.empty?
  
  # Delete photos for removed items
  date = DateTime.parse(created_at)
  year = date.year
  month = date.month.to_s.rjust(2, '0')
  day = date.day.to_s.rjust(2, '0')
  
  existing_items.each do |item|
    if removed_item_ids.include?(item['itemId'])
      # Delete all photos for this item using itemId
      prefix = "#{year}/#{month}/#{day}/#{user_id}/#{quote_id}/#{item['itemId']}/"
      S3Client.delete_item_photos(bucket_name, prefix)
      puts "Deleted photos for removed item #{item['itemId']} at prefix: #{prefix}"
    end
  end
end
