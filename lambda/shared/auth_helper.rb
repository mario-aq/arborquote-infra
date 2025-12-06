# Authentication helper for JWT token validation and user context extraction
module AuthHelper
  # Extract user information from JWT claims
  # @param event [Hash] API Gateway event
  # @return [Hash] User context with userId and username
  # @raise [AuthenticationError] if JWT is missing or invalid
  def self.extract_user_from_jwt(event)
    claims = event.dig('requestContext', 'authorizer', 'jwt', 'claims')

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
