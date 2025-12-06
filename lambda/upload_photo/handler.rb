require 'json'
require_relative '../shared/db_client'
require_relative '../shared/s3_client'

# Lambda handler for uploading photos
# POST /photos
# Returns S3 keys that can be used in quote items
def lambda_handler(event:, context:)
  # Parse request body
  body = JSON.parse(event['body'] || '{}')

  # Validate request size
  ValidationHelper.validate_request_size(event)
  
  # Validate required fields
  unless body['userId'] && !body['userId'].strip.empty?
    return ResponseHelper.error(400, 'ValidationError', 'userId is required')
  end
  
  unless body['photos'] && body['photos'].is_a?(Array) && !body['photos'].empty?
    return ResponseHelper.error(400, 'ValidationError', 'photos array is required and must not be empty')
  end

  user_id = body['userId']
  puts "Uploading #{body['photos'].length} photos for user #{user_id}"

  # Validate photos
  ValidationHelper.validate_photos(body['photos'])
  
  bucket_name = ENV['PHOTOS_BUCKET_NAME']
  user_id = body['userId']
  timestamp = DbClient.current_timestamp
  
  # Generate a temporary photo group ID for organizing these uploads
  # This allows photos to be uploaded before the quote exists
  photo_group_id = body['quoteId'] || "temp-#{DbClient.generate_ulid}"
  # Use provided itemId, or generate a temp one for organization
  item_id = body['itemId'] || "temp-#{DbClient.generate_ulid}"
  
  # Upload photos to S3
  uploaded_keys = body['photos'].map.with_index do |photo_data, photo_idx|
    # Determine filename and extension
    filename = photo_data['filename'] || "photo-#{photo_idx + 1}"
    extension = S3Client.extension_from_content_type(photo_data['contentType'])
    filename_with_ext = filename.include?('.') ? filename : "#{filename}.#{extension}"
    
    # Generate S3 key using itemId
    s3_key = S3Client.generate_photo_key(
      timestamp,
      user_id,
      photo_group_id,
      item_id,
      filename_with_ext
    )
    
    # Upload to S3
    S3Client.upload_photo_base64(
      bucket_name,
      s3_key,
      photo_data['data'],
      photo_data['contentType']
    )
    
    puts "Uploaded photo: #{s3_key}"
    
    {
      's3Key' => s3_key,
      'filename' => filename_with_ext,
      'contentType' => photo_data['contentType']
    }
  end
  
  # Return uploaded photo keys
  response = {
    'photos' => uploaded_keys,
    'uploadedAt' => timestamp
  }
  
  ResponseHelper.success(201, response)
  
rescue ValidationHelper::ValidationError => e
  puts "Validation error: #{e.message}"
  ResponseHelper.error(400, 'ValidationError', e.message)
rescue S3Client::S3Error => e
  puts "S3 error: #{e.message}"
  ResponseHelper.error(500, 'S3Error', "Failed to upload photos: #{e.message}")
rescue JSON::ParserError => e
  puts "JSON parse error: #{e.message}"
  ResponseHelper.error(400, 'InvalidJSON', 'Request body must be valid JSON')
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
  puts e.backtrace
  ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
end

