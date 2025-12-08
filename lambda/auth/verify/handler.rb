require 'json'
require 'aws-sdk-cognitoidentityprovider'
require 'digest'

require_relative '../../shared/db_client'

# Validation helper (inline for now)
module ValidationHelper
  MAX_REQUEST_SIZE_BYTES = 10 * 1024 * 1024  # 10MB (API Gateway limit)

  def self.validate_request_size(event)
    body_size = event.dig('body')&.bytesize || 0
    if body_size > MAX_REQUEST_SIZE_BYTES
      raise ValidationError.new('Request body too large')
    end
  end

  class ValidationError < StandardError
  end
end

# Lambda handler for confirming signup verification codes
# POST /auth/verify
def lambda_handler(event:, context:)
  begin
    # Parse request body
    body = JSON.parse(event['body'] || '{}')

    # Validate request size
    ValidationHelper.validate_request_size(event)

    # Validate required fields
    email = body['email']
    verification_code = body['verificationCode']

    unless email && !email.strip.empty?
      return error_response(400, 'ValidationError', 'Email is required')
    end

    unless email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      return error_response(400, 'ValidationError', 'Invalid email format')
    end

    unless verification_code && !verification_code.strip.empty?
      return error_response(400, 'ValidationError', 'Verification code is required')
    end

    email = email.downcase.strip

    # Initialize Cognito client
    cognito = Aws::CognitoIdentityProvider::Client.new(region: ENV['AWS_REGION'])

    begin
      # Confirm the verification code
      cognito.confirm_sign_up(
        client_id: ENV['COGNITO_CLIENT_ID'],
        username: email,
        confirmation_code: verification_code
      )

      # Create user profile in DynamoDB after successful verification
      create_verified_user_profile(email)

      # Return success response
      success_response({
        message: "Email verified successfully",
        email: email
      })

    rescue Aws::CognitoIdentityProvider::Errors::CodeMismatchException
      return error_response(400, 'InvalidCode', 'Invalid verification code')
    rescue Aws::CognitoIdentityProvider::Errors::ExpiredCodeException
      return error_response(400, 'ExpiredCode', 'Verification code has expired')
    rescue Aws::CognitoIdentityProvider::Errors::NotAuthorizedException
      return error_response(400, 'NotAuthorized', 'User is already confirmed or code is invalid')
    rescue Aws::CognitoIdentityProvider::Errors::UserNotFoundException
      return error_response(404, 'UserNotFound', 'User not found')
    rescue Aws::CognitoIdentityProvider::Errors::TooManyFailedAttemptsException
      return error_response(429, 'TooManyAttempts', 'Too many failed verification attempts')
    rescue Aws::CognitoIdentityProvider::Errors::LimitExceededException
      return error_response(429, 'RateLimitExceeded', 'Too many requests. Please try again later.')
    end

  rescue JSON::ParserError
    return error_response(400, 'ValidationError', 'Invalid JSON in request body')
  rescue => e
    puts "Verify error: #{e.message}"
    return error_response(500, 'InternalServerError', 'An unexpected error occurred')
  end
end

# Create user profile in DynamoDB after successful email verification
def create_verified_user_profile(email)
  begin
    # Get user attributes from Cognito
    cognito = Aws::CognitoIdentityProvider::Client.new(region: ENV['AWS_REGION'])
    user_response = cognito.admin_get_user(
      user_pool_id: ENV['COGNITO_USER_POOL_ID'],
      username: email
    )

    # Extract user attributes
    user_attributes = {}
    user_sub = nil
    user_response.user_attributes.each do |attr|
      case attr.name
      when 'sub'
        user_sub = attr.value
      when 'email'
        user_attributes['email'] = attr.value
      when 'name'
        user_attributes['name'] = attr.value
      end
    end

    # Use Cognito sub as user ID
    user_id = user_sub

    # Check if user record already exists
    users_table = ENV['USERS_TABLE_NAME']
    existing_user = DbClient.get_item(users_table, { 'userId' => user_id })

    if existing_user
      puts "User record already exists for #{email}, skipping creation"
      return
    end

    # Create user record in DynamoDB
    timestamp = DbClient.current_timestamp

    user_record = {
      'userId' => user_id,
      'email' => email,
      'name' => user_attributes['name'] || '',
      'phone' => nil,
      'address' => nil,
      'companyId' => nil, # Will be set later when user joins/creates company
      'createdAt' => timestamp,
      'updatedAt' => timestamp
    }.compact # Remove nil values

    puts "Creating verified user profile: #{user_record.inspect}"
    DbClient.put_item(users_table, user_record)

  rescue => e
    puts "Failed to create user profile: #{e.message}"
    # Don't fail the verification if user profile creation fails
    # The user can still log in, but profile operations might not work
  end
end

# Success response helper
def success_response(data)
  {
    statusCode: 200,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: JSON.generate(data)
  }
end


# Error response helper
def error_response(status_code, error_type, message)
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
