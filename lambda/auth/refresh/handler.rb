require 'json'
require 'aws-sdk-cognitoidentityprovider'
require_relative '../../shared/db_client'

# Lambda handler for token refresh
# POST /auth/refresh
def lambda_handler(event:, context:)
  begin
    # Parse request body
    body = JSON.parse(event['body'] || '{}')

    # Validate request size
    ValidationHelper.validate_request_size(event)

    # Validate required fields
    refresh_token = body['refreshToken']

    unless refresh_token && !refresh_token.strip.empty?
      return error_response(400, 'ValidationError', 'Refresh token is required')
    end

    # Initialize Cognito client
    cognito = Aws::CognitoIdentityProvider::Client.new(region: ENV['AWS_REGION'])

    begin
      # Refresh tokens
      response = cognito.admin_initiate_auth(
        user_pool_id: ENV['COGNITO_USER_POOL_ID'],
        client_id: ENV['COGNITO_CLIENT_ID'],
        auth_flow: 'REFRESH_TOKEN_AUTH',
        auth_parameters: {
          'REFRESH_TOKEN' => refresh_token
        }
      )

      # Extract new access and ID tokens
      tokens = response.authentication_result

      success_response({
        accessToken: tokens.access_token,
        idToken: tokens.id_token,
        expiresIn: tokens.expires_in,
        tokenType: 'Bearer'
      })

    rescue Aws::CognitoIdentityProvider::Errors::NotAuthorizedException
      return error_response(401, 'AuthenticationError', 'Invalid or expired refresh token')
    rescue Aws::CognitoIdentityProvider::Errors::UserNotFoundException
      return error_response(401, 'AuthenticationError', 'User account not found')
    rescue Aws::CognitoIdentityProvider::Errors::TooManyRequestsException
      return error_response(429, 'RateLimitError', 'Too many refresh attempts. Please try again later.')
    end

  rescue JSON::ParserError
    return error_response(400, 'ValidationError', 'Invalid JSON in request body')
  rescue => e
    puts "Token refresh error: #{e.message}"
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
