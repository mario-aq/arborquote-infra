require 'aws-sdk-dynamodb'
require 'json'
require 'securerandom'

# Shared DynamoDB client and utility functions for all Lambda handlers
module DbClient
  class << self
    # Lazy-load DynamoDB client
    def dynamodb_client
      @dynamodb_client ||= Aws::DynamoDB::Client.new
    end

    # Generate a ULID-like ID (time-sortable, URL-safe)
    # Format: timestamp (10 chars) + random (16 chars) = 26 chars
    def generate_ulid
      timestamp = (Time.now.to_f * 1000).to_i.to_s(36).upcase.rjust(10, '0')
      random = SecureRandom.alphanumeric(16).upcase
      "#{timestamp}#{random}"
    end

    # Get current ISO 8601 timestamp
    def current_timestamp
      Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%LZ')
    end

    # DynamoDB get_item wrapper
    def get_item(table_name, key)
      response = dynamodb_client.get_item(
        table_name: table_name,
        key: key
      )
      response.item
    rescue Aws::DynamoDB::Errors::ServiceError => e
      raise DbError.new("Failed to get item: #{e.message}")
    end

    # DynamoDB put_item wrapper
    def put_item(table_name, item)
      dynamodb_client.put_item(
        table_name: table_name,
        item: item
      )
    rescue Aws::DynamoDB::Errors::ServiceError => e
      raise DbError.new("Failed to put item: #{e.message}")
    end

    # DynamoDB update_item wrapper
    def update_item(table_name, key, updates)
      update_expression_parts = []
      expression_attribute_names = {}
      expression_attribute_values = {}

      updates.each_with_index do |(attr, value), index|
        placeholder = "#attr#{index}"
        value_placeholder = ":val#{index}"
        
        update_expression_parts << "#{placeholder} = #{value_placeholder}"
        expression_attribute_names[placeholder] = attr
        expression_attribute_values[value_placeholder] = value
      end

      response = dynamodb_client.update_item(
        table_name: table_name,
        key: key,
        update_expression: "SET #{update_expression_parts.join(', ')}",
        expression_attribute_names: expression_attribute_names,
        expression_attribute_values: expression_attribute_values,
        return_values: 'ALL_NEW'
      )
      
      response.attributes
    rescue Aws::DynamoDB::Errors::ServiceError => e
      raise DbError.new("Failed to update item: #{e.message}")
    end

    # DynamoDB query wrapper (for GSI queries)
    def query(table_name, index_name: nil, key_condition_expression:, expression_attribute_names: {}, expression_attribute_values: {})
      params = {
        table_name: table_name,
        key_condition_expression: key_condition_expression,
        expression_attribute_names: expression_attribute_names,
        expression_attribute_values: expression_attribute_values
      }
      
      params[:index_name] = index_name if index_name
      
      response = dynamodb_client.query(params)
      response.items
    rescue Aws::DynamoDB::Errors::ServiceError => e
      raise DbError.new("Failed to query: #{e.message}")
    end
  end

  # Custom error class for database operations
  class DbError < StandardError; end
end

# Response formatting utilities
module ResponseHelper
  def self.success(status_code, body)
    {
      statusCode: status_code,
      headers: {
        'Content-Type' => 'application/json',
        'Access-Control-Allow-Origin' => '*'
      },
      body: JSON.generate(body)
    }
  end

  def self.error(status_code, error_type, message)
    {
      statusCode: status_code,
      headers: {
        'Content-Type' => 'application/json',
        'Access-Control-Allow-Origin' => '*'
      },
      body: JSON.generate({
        error: error_type,
        message: message
      })
    }
  end
end

# Input validation utilities
module ValidationHelper
  VALID_STATUSES = ['draft', 'sent', 'accepted', 'rejected'].freeze
  VALID_ITEM_TYPES = [
    'tree_removal',
    'pruning',
    'stump_grinding',
    'cleanup',
    'trimming',
    'emergency_service',
    'other'
  ].freeze
  
  # Photo validation constants
  MAX_ITEMS_PER_QUOTE = 10
  MAX_PHOTOS_PER_ITEM = 3
  MAX_PHOTO_SIZE_BYTES = 5 * 1024 * 1024  # 5MB
  ALLOWED_PHOTO_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'].freeze

  def self.validate_required_fields(data, required_fields)
    missing_fields = required_fields.select { |field| data[field].nil? || data[field].to_s.strip.empty? }
    
    unless missing_fields.empty?
      raise ValidationError.new("Missing required fields: #{missing_fields.join(', ')}")
    end
  end

  def self.validate_quote_status(status)
    unless VALID_STATUSES.include?(status)
      raise ValidationError.new("Invalid status. Must be one of: #{VALID_STATUSES.join(', ')}")
    end
  end

  def self.validate_item_type(type)
    unless VALID_ITEM_TYPES.include?(type)
      raise ValidationError.new("Invalid item type. Must be one of: #{VALID_ITEM_TYPES.join(', ')}")
    end
  end

  def self.validate_items(items)
    if items.nil? || !items.is_a?(Array)
      raise ValidationError.new("Items must be an array")
    end

    if items.empty?
      raise ValidationError.new("Quote must have at least one item")
    end

    if items.length > MAX_ITEMS_PER_QUOTE
      raise ValidationError.new("Quote can have maximum #{MAX_ITEMS_PER_QUOTE} items")
    end

    items.each_with_index do |item, index|
      validate_item(item, index)
    end
  end

  def self.validate_item(item, index = 0)
    # Required fields for each item
    required_fields = ['type', 'description']
    required_fields.each do |field|
      if item[field].nil? || item[field].to_s.strip.empty?
        raise ValidationError.new("Item #{index}: Missing required field '#{field}'")
      end
    end

    # Validate item type
    validate_item_type(item['type'])

    # Validate price if provided
    if item['price'] && (!item['price'].is_a?(Integer) || item['price'] < 0)
      raise ValidationError.new("Item #{index}: Price must be a non-negative integer (cents)")
    end

    # Validate numeric fields if provided
    if item['diameterInInches'] && (!item['diameterInInches'].is_a?(Numeric) || item['diameterInInches'] <= 0)
      raise ValidationError.new("Item #{index}: diameterInInches must be a positive number")
    end

    if item['heightInFeet'] && (!item['heightInFeet'].is_a?(Numeric) || item['heightInFeet'] <= 0)
      raise ValidationError.new("Item #{index}: heightInFeet must be a positive number")
    end

    # Validate arrays
    if item['riskFactors'] && !item['riskFactors'].is_a?(Array)
      raise ValidationError.new("Item #{index}: riskFactors must be an array")
    end

    if item['photos'] && !item['photos'].is_a?(Array)
      raise ValidationError.new("Item #{index}: photos must be an array")
    end
    
    # Validate photos if present
    if item['photos'] && !item['photos'].empty?
      validate_photos(item['photos'], index)
    end
  end
  
  def self.validate_photos(photos, item_index = 0)
    if photos.length > MAX_PHOTOS_PER_ITEM
      raise ValidationError.new("Item #{item_index}: Maximum #{MAX_PHOTOS_PER_ITEM} photos allowed per item")
    end
    
    photos.each_with_index do |photo, photo_index|
      validate_photo(photo, item_index, photo_index)
    end
  end
  
  def self.validate_photo(photo, item_index = 0, photo_index = 0)
    # Photo must be a hash with 'data' and 'contentType'
    unless photo.is_a?(Hash)
      raise ValidationError.new("Item #{item_index}, Photo #{photo_index}: Photo must be an object")
    end
    
    unless photo['data']
      raise ValidationError.new("Item #{item_index}, Photo #{photo_index}: Photo must have 'data' field")
    end
    
    unless photo['contentType']
      raise ValidationError.new("Item #{item_index}, Photo #{photo_index}: Photo must have 'contentType' field")
    end
    
    # Validate content type
    unless ALLOWED_PHOTO_CONTENT_TYPES.include?(photo['contentType'])
      raise ValidationError.new("Item #{item_index}, Photo #{photo_index}: Invalid content type '#{photo['contentType']}'. Allowed types: #{ALLOWED_PHOTO_CONTENT_TYPES.join(', ')}")
    end
    
    # Validate base64 data format (basic check)
    unless photo['data'].is_a?(String) && photo['data'].match?(/^[A-Za-z0-9+\/]+=*$/)
      raise ValidationError.new("Item #{item_index}, Photo #{photo_index}: Invalid base64 data format")
    end
    
    # Estimate decoded size (base64 encoding increases size by ~33%)
    estimated_size = (photo['data'].length * 3) / 4
    if estimated_size > MAX_PHOTO_SIZE_BYTES
      raise ValidationError.new("Item #{item_index}, Photo #{photo_index}: Photo size exceeds maximum of #{MAX_PHOTO_SIZE_BYTES / 1024 / 1024}MB")
    end
  end

  # Custom error class for validation
  class ValidationError < StandardError; end
end

# Item processing utilities
module ItemHelper
  def self.build_item(item_data)
    {
      'itemId' => DbClient.generate_ulid,
      'type' => item_data['type'],
      'description' => item_data['description'],
      'diameterInInches' => item_data['diameterInInches'],
      'heightInFeet' => item_data['heightInFeet'],
      'riskFactors' => item_data['riskFactors'] || [],
      'price' => item_data['price'] || 0,
      'photos' => item_data['photos'] || []
    }
  end

  def self.calculate_total_price(items)
    items.sum { |item| item['price'] || 0 }
  end
end

