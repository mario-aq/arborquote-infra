require 'json'
require 'aws-sdk-cognitoidentityprovider'

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
