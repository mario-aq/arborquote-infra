require 'json'
require 'aws-sdk-cognitoidentityprovider'

# Lambda handler for responding to authentication challenges
# POST /auth/challenge
def lambda_handler(event:, context:)
  begin
    # Parse request body
    body = JSON.parse(event['body'] || '{}')

    # Validate request size
    ValidationHelper.validate_request_size(event)

    # Validate required fields
    username = body['username']
    challenge_name = body['challengeName']
    challenge_response = body['challengeResponse'] # Hash with challenge-specific responses
    session = body['session']

    unless username && !username.strip.empty?
      return error_response(400, 'ValidationError', 'Username is required')
    end

    unless challenge_name && !challenge_name.strip.empty?
      return error_response(400, 'ValidationError', 'Challenge name is required')
    end

    unless challenge_response && challenge_response.is_a?(Hash)
      return error_response(400, 'ValidationError', 'Challenge response must be an object')
    end

    unless session && !session.strip.empty?
      return error_response(400, 'ValidationError', 'Session token is required')
    end

    # Initialize Cognito client
    cognito = Aws::CognitoIdentityProvider::Client.new(region: ENV['AWS_REGION'])

    begin
      # Build challenge responses based on challenge type
      challenge_responses = { 'USERNAME' => username }

      case challenge_name
      when 'SMS_MFA'
        mfa_code = challenge_response['SMS_MFA_CODE']
        unless mfa_code && !mfa_code.strip.empty?
          return error_response(400, 'ValidationError', 'SMS_MFA_CODE is required')
        end
        challenge_responses['SMS_MFA_CODE'] = mfa_code

      when 'SOFTWARE_TOKEN_MFA'
        mfa_code = challenge_response['SOFTWARE_TOKEN_MFA_CODE']
        unless mfa_code && !mfa_code.strip.empty?
          return error_response(400, 'ValidationError', 'SOFTWARE_TOKEN_MFA_CODE is required')
        end
        challenge_responses['SOFTWARE_TOKEN_MFA_CODE'] = mfa_code

      when 'NEW_PASSWORD_REQUIRED'
        new_password = challenge_response['NEW_PASSWORD']
        unless new_password && new_password.length >= 8
          return error_response(400, 'ValidationError', 'NEW_PASSWORD must be at least 8 characters long')
        end
        challenge_responses['NEW_PASSWORD'] = new_password

      else
        return error_response(400, 'UnsupportedChallenge', "Challenge type '#{challenge_name}' is not supported")
      end

      # Respond to the authentication challenge
      response = cognito.respond_to_auth_challenge(
        client_id: ENV['COGNITO_CLIENT_ID'],
        challenge_name: challenge_name,
        challenge_responses: challenge_responses,
        session: session
      )

      # Check if authentication is complete or another challenge is needed
      if response.authentication_result
        # Authentication successful
        tokens = response.authentication_result
        success_response({
          message: 'Authentication successful',
          accessToken: tokens.access_token,
          refreshToken: tokens.refresh_token,
          idToken: tokens.id_token,
          expiresIn: tokens.expires_in,
          tokenType: 'Bearer'
        })
      elsif response.challenge_name
        # Another challenge is required
        challenge_response({
          challenge: response.challenge_name,
          session: response.session,
          parameters: response.challenge_parameters || {}
        })
      else
        return error_response(500, 'InternalServerError', 'Unexpected authentication response')
      end

    rescue Aws::CognitoIdentityProvider::Errors::CodeMismatchException
      return error_response(400, 'InvalidCode', 'Invalid verification code')
    rescue Aws::CognitoIdentityProvider::Errors::ExpiredCodeException
      return error_response(400, 'ExpiredCode', 'Verification code has expired')
    rescue Aws::CognitoIdentityProvider::Errors::NotAuthorizedException
      return error_response(401, 'NotAuthorized', 'Invalid credentials or session')
    rescue Aws::CognitoIdentityProvider::Errors::UserNotFoundException
      return error_response(404, 'UserNotFound', 'User not found')
    rescue Aws::CognitoIdentityProvider::Errors::TooManyFailedAttemptsException
      return error_response(429, 'TooManyAttempts', 'Too many failed attempts')
    rescue Aws::CognitoIdentityProvider::Errors::LimitExceededException
      return error_response(429, 'RateLimitExceeded', 'Too many requests. Please try again later.')
    rescue Aws::CognitoIdentityProvider::Errors::InvalidPasswordException
      return error_response(400, 'InvalidPassword', 'Password does not meet requirements')
    end

  rescue JSON::ParserError
    return error_response(400, 'ValidationError', 'Invalid JSON in request body')
  rescue => e
    puts "Challenge response error: #{e.message}"
    return error_response(500, 'InternalServerError', 'An unexpected error occurred')
  end
end

# Success response helper (authentication complete)
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

# Challenge response helper (another challenge required)
def challenge_response(data)
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
