require 'json'
require 'aws-sdk-cognitoidentityprovider'

# Lambda handler for user signup
# POST /auth/signup
def lambda_handler(event:, context:)
  begin
    # Parse request body
    body = JSON.parse(event['body'] || '{}')

    # Validate request size
    ValidationHelper.validate_request_size(event)

    # Validate required fields
    email = body['email']
    password = body['password']
    name = body['name']

    unless email && !email.strip.empty?
      return error_response(400, 'ValidationError', 'Email is required')
    end

    unless password && password.length >= 8
      return error_response(400, 'ValidationError', 'Password must be at least 8 characters long')
    end

    unless name && !name.strip.empty?
      return error_response(400, 'ValidationError', 'Name is required')
    end

    # Initialize Cognito client
    cognito = Aws::CognitoIdentityProvider::Client.new(region: ENV['AWS_REGION'])

    begin
      # Create user account
      cognito.sign_up(
        client_id: ENV['COGNITO_CLIENT_ID'],
        username: email,
        password: password,
        user_attributes: [
          {
            name: 'email',
            value: email
          },
          {
            name: 'name',
            value: name
          }
        ]
      )

      # Auto-confirm user (for development/demo purposes)
      # In production, you might want users to confirm via email
      if ENV['AUTO_CONFIRM_USERS'] == 'true'
        cognito.admin_confirm_sign_up(
          user_pool_id: ENV['COGNITO_USER_POOL_ID'],
          username: email
        )
      end

      success_response({
        message: 'User account created successfully',
        email: email,
        confirmed: ENV['AUTO_CONFIRM_USERS'] == 'true'
      })

    rescue Aws::CognitoIdentityProvider::Errors::UsernameExistsException
      return error_response(409, 'ValidationError', 'An account with this email already exists')
    rescue Aws::CognitoIdentityProvider::Errors::InvalidPasswordException
      return error_response(400, 'ValidationError', 'Password does not meet requirements')
    rescue Aws::CognitoIdentityProvider::Errors::InvalidParameterException => e
      return error_response(400, 'ValidationError', 'Invalid email format or other parameter error')
    rescue Aws::CognitoIdentityProvider::Errors::TooManyRequestsException
      return error_response(429, 'RateLimitError', 'Too many signup attempts. Please try again later.')
    end

  rescue JSON::ParserError
    return error_response(400, 'ValidationError', 'Invalid JSON in request body')
  rescue => e
    puts "Signup error: #{e.message}"
    return error_response(500, 'InternalServerError', 'An unexpected error occurred')
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
