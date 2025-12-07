require 'json'
require_relative '../shared/auth_helper'
require_relative '../shared/db_client'

# Lambda handler for updating user profile
# PUT /user
def lambda_handler(event:, context:)
  begin
    # Extract authenticated user from JWT
    user = AuthHelper.extract_user_from_jwt(event)

    # Parse request body
    body = JSON.parse(event['body'] || '{}')

    # Validate request size
    ValidationHelper.validate_request_size(event)

    # Get user ID from JWT
    user_id = user[:user_id]

    puts "Updating user profile for: #{user_id}"

    # Fetch existing user from DynamoDB
    users_table = ENV['USERS_TABLE_NAME']
    existing_user = DbClient.get_item(users_table, { 'userId' => user_id })

    if existing_user.nil?
      puts "User not found: #{user_id}"
      return ResponseHelper.error(404, 'UserNotFound', 'User profile not found')
    end

    # Validate ownership (user can only update their own profile)
    AuthHelper.validate_resource_ownership(user_id, existing_user['userId'])

    # Validate and prepare update data
    update_data = validate_update_data(body)

    if update_data.empty?
      return ResponseHelper.error(400, 'ValidationError', 'At least one field must be provided for update')
    end

    # Add updated timestamp
    update_data['updatedAt'] = DbClient.current_timestamp

    puts "Updating user with data: #{update_data.keys.join(', ')}"

    # Update user in DynamoDB
    updated_user = DbClient.update_item(
      users_table,
      { 'userId' => user_id },
      update_data
    )

    puts "User profile updated successfully: #{user_id}"

    # Return updated user (merge existing with updates for response)
    response_user = existing_user.merge(update_data)
    ResponseHelper.success(200, response_user)

  rescue AuthenticationError => e
    puts "Authentication error: #{e.message}"
    ResponseHelper.error(401, 'AuthenticationError', e.message)
  rescue AuthorizationError => e
    puts "Authorization error: #{e.message}"
    ResponseHelper.error(403, 'AuthorizationError', e.message)
  rescue ValidationHelper::ValidationError => e
    puts "Validation error: #{e.message}"
    ResponseHelper.error(400, 'ValidationError', e.message)
  rescue DbClient::DbError => e
    puts "Database error: #{e.message}"
    ResponseHelper.error(500, 'DatabaseError', 'Failed to update user profile')
  rescue JSON::ParserError => e
    puts "JSON parse error: #{e.message}"
    ResponseHelper.error(400, 'ValidationError', 'Request body must be valid JSON')
  rescue StandardError => e
    puts "Unexpected error: #{e.message}"
    puts e.backtrace.join("\n")
    ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
  end
rescue StandardError => e
  puts "Unhandled error: #{e.message}"
  puts e.backtrace.join("\n")
  {
    statusCode: 500,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: JSON.generate({
      error: 'InternalServerError',
      message: 'An unexpected error occurred'
    })
  }
end

# Validate and sanitize update data
def validate_update_data(body)
  update_data = {}

  # Validate name (required if provided)
  if body.key?('name')
    name = body['name']
    if name.nil? || name.strip.empty?
      raise ValidationHelper::ValidationError.new('Name cannot be empty')
    end
    update_data['name'] = name.strip
  end

  # Validate email (required if provided)
  if body.key?('email')
    email = body['email']
    if email.nil? || email.strip.empty?
      raise ValidationHelper::ValidationError.new('Email cannot be empty')
    end

    # Basic email validation
    unless email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      raise ValidationHelper::ValidationError.new('Invalid email format')
    end

    update_data['email'] = email.strip.downcase
  end

  # Validate phone (optional)
  if body.key?('phone')
    phone = body['phone']
    if phone && !phone.strip.empty?
      # Basic phone validation (allow various formats)
      clean_phone = phone.gsub(/[^\d+\-\(\)\s\.]/, '').strip
      if clean_phone.length < 7
        raise ValidationHelper::ValidationError.new('Phone number is too short')
      end
      update_data['phone'] = phone.strip
    end
  end

  # Validate address (optional)
  if body.key?('address')
    address = body['address']
    if address && !address.strip.empty?
      update_data['address'] = address.strip
    end
  end

  # Note: companyId is read-only and cannot be updated via this endpoint

  update_data
end
