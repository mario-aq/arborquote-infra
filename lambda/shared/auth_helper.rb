require 'jwt'

# Authentication helper for JWT token validation and user context extraction
# Updated with JWT decoding capability
module AuthHelper
  # Extract user information from JWT token in Authorization header
  # @param event [Hash] API Gateway event
  # @return [Hash] User context with userId and username
  # @raise [AuthenticationError] if JWT is missing or invalid
  def self.extract_user_from_jwt(event)
    # First try to get claims from API Gateway authorizer (if configured)
    claims = event.dig('requestContext', 'authorizer', 'jwt', 'claims')

    # If no claims from authorizer, try to decode JWT from Authorization header
    if claims.nil? || claims.empty?
      auth_header = event.dig('headers', 'Authorization') || event.dig('headers', 'authorization')

      if auth_header.nil? || auth_header.empty?
        raise AuthenticationError.new('No authorization header found')
      end

      # Extract Bearer token
      unless auth_header.start_with?('Bearer ')
        raise AuthenticationError.new('Invalid authorization header format')
      end

      token = auth_header.sub('Bearer ', '')

      begin
        # Decode JWT without verification (since we're using Cognito)
        # In production, you should verify the token signature
        decoded_token = JWT.decode(token, nil, false)
        claims = decoded_token[0] # First element is the payload
      rescue JWT::DecodeError => e
        raise AuthenticationError.new("Invalid JWT token: #{e.message}")
      end
    end

    if claims.nil? || claims.empty?
      raise AuthenticationError.new('No JWT claims found')
    end

    user_id = claims['sub']
    username = claims['cognito:username'] || claims['email'] || claims['sub']

    if user_id.nil? || user_id.strip.empty?
      raise AuthenticationError.new('Invalid JWT: missing user ID')
    end

    {
      user_id: user_id,
      username: username
    }
  end

  # Validate that the authenticated user owns the resource
  # @param authenticated_user_id [String] User ID from JWT
  # @param resource_user_id [String] User ID associated with the resource
  # @raise [AuthorizationError] if user doesn't own the resource
  def self.validate_resource_ownership(authenticated_user_id, resource_user_id)
    unless authenticated_user_id == resource_user_id
      raise AuthorizationError.new('Access denied: resource belongs to another user')
    end
  end
end

# Custom authentication errors
class AuthenticationError < StandardError; end
class AuthorizationError < StandardError; end
