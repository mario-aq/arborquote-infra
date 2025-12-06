require 'json'
require 'aws-sdk-cognitoidentityprovider'

# Lambda handler for user login
# POST /auth/login
def lambda_handler(event:, context:)
  begin
    # Parse request body
    body = JSON.parse(event['body'] || '{}')

    # Validate request size
    ValidationHelper.validate_request_size(event)

    # Validate required fields
    email = body['email']
    password = body['password']

    unless email && !email.strip.empty?
      return error_response(400, 'ValidationError', 'Email is required')
    end

    unless password && !password.strip.empty?
      return error_response(400, 'ValidationError', 'Password is required')
    end

    # Initialize Cognito client
    cognito = Aws::CognitoIdentityProvider::Client.new(region: ENV['AWS_REGION'])

    begin
      # Authenticate user
      response = cognito.admin_initiate_auth(
        user_pool_id: ENV['COGNITO_USER_POOL_ID'],
        client_id: ENV['COGNITO_CLIENT_ID'],
        auth_flow: 'ADMIN_USER_PASSWORD_AUTH',
        auth_parameters: {
          'USERNAME' => email,
          'PASSWORD' => password
        }
      )

      # Extract tokens
      tokens = response.authentication_result

      success_response({
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token,
        idToken: tokens.id_token,
        expiresIn: tokens.expires_in,
        tokenType: 'Bearer'
      })

    rescue Aws::CognitoIdentityProvider::Errors::NotAuthorizedException
      return error_response(401, 'AuthenticationError', 'Invalid email or password')
    rescue Aws::CognitoIdentityProvider::Errors::UserNotConfirmedException
      return error_response(401, 'AuthenticationError', 'User account not confirmed')
    rescue Aws::CognitoIdentityProvider::Errors::UserNotFoundException
      return error_response(401, 'AuthenticationError', 'User account not found')
    rescue Aws::CognitoIdentityProvider::Errors::TooManyRequestsException
      return error_response(429, 'RateLimitError', 'Too many login attempts. Please try again later.')
    end

  rescue JSON::ParserError
    return error_response(400, 'ValidationError', 'Invalid JSON in request body')
  rescue => e
    puts "Login error: #{e.message}"
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
