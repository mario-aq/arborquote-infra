require 'json'
require_relative '../shared/db_client'
require_relative '../shared/s3_client'

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
  user_id = body['userId']
  bucket_name = ENV['PHOTOS_BUCKET_NAME']
  
  # Process items - generate itemIds and upload photos to S3
  items = body['items'].map.with_index do |item_data, index|
    ValidationHelper.validate_item(item_data)
    item = ItemHelper.build_item(item_data)
    
    # Handle photo uploads if present
    if item_data['photos'] && !item_data['photos'].empty?
      uploaded_photo_keys = item_data['photos'].map.with_index do |photo_data, photo_idx|
        if photo_data.is_a?(String)
          # Already an S3 key (from independent upload) - use as-is
          photo_data
        elsif photo_data.is_a?(Hash) && photo_data['data']
          # Base64 photo data - upload to S3
          filename = photo_data['filename'] || "photo-#{photo_idx + 1}"
          extension = S3Client.extension_from_content_type(photo_data['contentType'])
          filename_with_ext = filename.include?('.') ? filename : "#{filename}.#{extension}"
          
          # Generate S3 key
          s3_key = S3Client.generate_photo_key(
            timestamp,
            user_id,
            quote_id,
            index,
            filename_with_ext
          )
          
          # Upload to S3
          S3Client.upload_photo_base64(
            bucket_name,
            s3_key,
            photo_data['data'],
            photo_data['contentType']
          )
          
          s3_key  # Store S3 key, not URL
        else
          raise ValidationHelper::ValidationError, "Photo must be either an S3 key string or an object with 'data' and 'contentType'"
        end
      end
      
      # Replace photo data with S3 keys
      item['photos'] = uploaded_photo_keys
    end
    
    item
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
rescue S3Client::S3Error => e
  puts "S3 error: #{e.message}"
  ResponseHelper.error(500, 'S3Error', "Failed to upload photos: #{e.message}")
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
