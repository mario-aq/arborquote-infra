require 'aws-sdk-s3'
require 'base64'
require 'date'

module S3Client
  # Maximum photo size in bytes (5MB)
  MAX_PHOTO_SIZE = 5 * 1024 * 1024

  # Allowed content types for photos
  ALLOWED_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'].freeze

  class S3Error < StandardError; end

  # Generate S3 key for photo using date-based path structure
  # @param created_at [String] ISO8601 timestamp
  # @param user_id [String] User ID
  # @param quote_id [String] Quote ID
  # @param item_id [String] Item ID (ULID)
  # @param filename [String] Original filename
  # @return [String] S3 key path
  def self.generate_photo_key(created_at, user_id, quote_id, item_id, filename)
    date = DateTime.parse(created_at)
    sanitized_filename = sanitize_filename(filename)
    
    year = date.year
    month = date.month.to_s.rjust(2, '0')
    day = date.day.to_s.rjust(2, '0')
    
    "#{year}/#{month}/#{day}/#{user_id}/#{quote_id}/#{item_id}/#{sanitized_filename}"
  end

  # Upload base64-encoded photo to S3
  # @param bucket [String] S3 bucket name
  # @param key [String] S3 key path
  # @param base64_data [String] Base64-encoded image data
  # @param content_type [String] MIME type of the image
  # @return [String] S3 key of uploaded object
  def self.upload_photo_base64(bucket, key, base64_data, content_type)
    # Validate content type
    unless ALLOWED_CONTENT_TYPES.include?(content_type)
      raise S3Error, "Invalid content type: #{content_type}. Allowed types: #{ALLOWED_CONTENT_TYPES.join(', ')}"
    end

    # Decode base64 data
    begin
      decoded_data = Base64.strict_decode64(base64_data)
    rescue ArgumentError => e
      raise S3Error, "Invalid base64 data: #{e.message}"
    end

    # Validate size
    if decoded_data.bytesize > MAX_PHOTO_SIZE
      raise S3Error, "Photo size exceeds maximum of #{MAX_PHOTO_SIZE / 1024 / 1024}MB"
    end

    # Upload to S3
    begin
      s3_client.put_object(
        bucket: bucket,
        key: key,
        body: decoded_data,
        content_type: content_type,
        server_side_encryption: 'AES256'
      )
    rescue Aws::S3::Errors::ServiceError => e
      raise S3Error, "Failed to upload photo to S3: #{e.message}"
    end

    key
  end

  # Generate presigned GET URL for photo
  # @param bucket [String] S3 bucket name
  # @param key [String] S3 key path
  # @param expires_in [Integer] URL expiration time in seconds (default: 1 hour)
  # @return [String] Presigned URL
  def self.generate_presigned_url(bucket, key, expires_in: 3600)
    begin
      signer = Aws::S3::Presigner.new(client: s3_client)
      signer.presigned_url(
        :get_object,
        bucket: bucket,
        key: key,
        expires_in: expires_in
      )
    rescue Aws::S3::Errors::ServiceError => e
      raise S3Error, "Failed to generate presigned URL: #{e.message}"
    end
  end

  # Delete a single photo from S3
  # @param bucket [String] S3 bucket name
  # @param key [String] S3 key path
  def self.delete_photo(bucket, key)
    begin
      s3_client.delete_object(
        bucket: bucket,
        key: key
      )
    rescue Aws::S3::Errors::ServiceError => e
      # Log but don't fail - photo might already be deleted
      puts "Warning: Failed to delete photo #{key}: #{e.message}"
    end
  end

  # Delete all photos for an item (by prefix)
  # @param bucket [String] S3 bucket name
  # @param prefix [String] S3 key prefix (e.g., "2025/11/29/user_001/QUOTE123/0/")
  def self.delete_item_photos(bucket, prefix)
    begin
      # List all objects with the prefix
      response = s3_client.list_objects_v2(
        bucket: bucket,
        prefix: prefix
      )

      return if response.contents.empty?

      # Delete all objects
      objects_to_delete = response.contents.map { |obj| { key: obj.key } }
      
      s3_client.delete_objects(
        bucket: bucket,
        delete: {
          objects: objects_to_delete
        }
      )
    rescue Aws::S3::Errors::ServiceError => e
      # Log but don't fail
      puts "Warning: Failed to delete photos with prefix #{prefix}: #{e.message}"
    end
  end

  # Get file extension from content type
  # @param content_type [String] MIME type
  # @return [String] File extension
  def self.extension_from_content_type(content_type)
    case content_type
    when 'image/jpeg'
      'jpg'
    when 'image/png'
      'png'
    when 'image/webp'
      'webp'
    else
      'jpg' # Default fallback
    end
  end

  # Sanitize filename to remove special characters
  # @param filename [String] Original filename
  # @return [String] Sanitized filename
  def self.sanitize_filename(filename)
    # Remove path components
    basename = File.basename(filename)
    
    # Replace spaces and special chars with underscore
    basename.gsub(/[^a-zA-Z0-9.\-_]/, '_')
  end

  private

  # Get S3 client instance (singleton)
  def self.s3_client
    @s3_client ||= Aws::S3::Client.new
  end
end
