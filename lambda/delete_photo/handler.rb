require 'json'
require_relative '../shared/auth_helper'
require_relative '../shared/db_client'
require_relative '../shared/s3_client'

# Lambda handler for deleting a photo
# DELETE /photos
# Request body: { "s3Key": "2025/11/29/user_id/quote_id/0/photo.jpg" }
def lambda_handler(event:, context:)
  begin
    # Extract authenticated user from JWT
    user = AuthHelper.extract_user_from_jwt(event)
  # Parse request body
  body = JSON.parse(event['body'] || '{}')

  # Validate request size
  ValidationHelper.validate_request_size(event)
  
  # Validate required fields
  unless body['s3Key'] && !body['s3Key'].strip.empty?
    return ResponseHelper.error(400, 'ValidationError', 's3Key is required')

rescue AuthenticationError => e
  puts "Authentication error: #{e.message}"
  ResponseHelper.error(401, 'AuthenticationError', e.message)
rescue AuthorizationError => e
  puts "Authorization error: #{e.message}"
  ResponseHelper.error(403, 'AuthorizationError', e.message)  end

  s3_key = body['s3Key']
  puts "Deleting photo with S3 key: #{s3_key}"
  bucket_name = ENV['PHOTOS_BUCKET_NAME']
  
  # Validate that the s3Key belongs to the authenticated user
  user_id = user[:user_id]
  # Check if s3Key contains the user_id in the expected format (year/month/day/user_id/...)
  unless s3_key.include?("/#{user_id}/")
    return ResponseHelper.error(403, 'AuthorizationError', 'You can only delete your own photos')
  end
  
  # Delete photo from S3
  begin
    S3Client.delete_photo(bucket_name, s3_key)
    puts "Deleted photo: #{s3_key}"
    
    # Return success with 204 No Content
    {
      statusCode: 204,
      headers: {
        'Content-Type' => 'application/json',
        'Access-Control-Allow-Origin' => '*',
        'Access-Control-Allow-Headers' => 'Content-Type',
        'Access-Control-Allow-Methods' => 'DELETE,OPTIONS'
      },
      body: ''
    }
  rescue S3Client::S3Error => e
    # If photo doesn't exist, that's okay - idempotent delete
    if e.message.include?('NoSuchKey') || e.message.include?('Not Found')
      puts "Photo already deleted or doesn't exist: #{s3_key}"
      return {
        statusCode: 204,
        headers: {
          'Content-Type' => 'application/json',
          'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Headers' => 'Content-Type',
          'Access-Control-Allow-Methods' => 'DELETE,OPTIONS'
        },
        body: ''
      }
    end
    raise
  end
  
rescue ValidationHelper::ValidationError => e
  puts "Validation error: #{e.message}"
  ResponseHelper.error(400, 'ValidationError', e.message)

rescue AuthenticationError => e
  puts "Authentication error: #{e.message}"
  ResponseHelper.error(401, 'AuthenticationError', e.message)
rescue AuthorizationError => e
  puts "Authorization error: #{e.message}"
  ResponseHelper.error(403, 'AuthorizationError', e.message)rescue S3Client::S3Error => e
  puts "S3 error: #{e.message}"
  ResponseHelper.error(500, 'S3Error', "Failed to delete photo: #{e.message}")

rescue AuthenticationError => e
  puts "Authentication error: #{e.message}"
  ResponseHelper.error(401, 'AuthenticationError', e.message)
rescue AuthorizationError => e
  puts "Authorization error: #{e.message}"
  ResponseHelper.error(403, 'AuthorizationError', e.message)rescue JSON::ParserError => e
  puts "JSON parse error: #{e.message}"
  ResponseHelper.error(400, 'InvalidJSON', 'Request body must be valid JSON')

rescue AuthenticationError => e
  puts "Authentication error: #{e.message}"
  ResponseHelper.error(401, 'AuthenticationError', e.message)
rescue AuthorizationError => e
  puts "Authorization error: #{e.message}"
  ResponseHelper.error(403, 'AuthorizationError', e.message)rescue StandardError => e
  puts "Unexpected error: #{e.message}"
  puts e.backtrace
  ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')

rescue AuthenticationError => e
  puts "Authentication error: #{e.message}"
  ResponseHelper.error(401, 'AuthenticationError', e.message)
rescue AuthorizationError => e
  puts "Authorization error: #{e.message}"
  ResponseHelper.error(403, 'AuthorizationError', e.message)end

