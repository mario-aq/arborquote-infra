require 'json'
require_relative '../shared/auth_helper'
require_relative '../shared/db_client'

# Lambda handler for getting user profile
# GET /user
def lambda_handler(event:, context:)
  begin
    # Extract authenticated user from JWT
    user = AuthHelper.extract_user_from_jwt(event)

    # Get user ID from JWT
    user_id = user[:user_id]

    puts "Retrieving user profile for: #{user_id}"

    # Fetch user from DynamoDB
    users_table = ENV['USERS_TABLE_NAME']
    user_profile = DbClient.get_item(users_table, { 'userId' => user_id })

    if user_profile.nil?
      puts "User not found: #{user_id}"
      return ResponseHelper.error(404, 'UserNotFound', 'User profile not found')
    end

    puts "User profile retrieved successfully: #{user_id}"

    # Return user profile
    ResponseHelper.success(200, user_profile)

  rescue AuthenticationError => e
    puts "Authentication error: #{e.message}"
    ResponseHelper.error(401, 'AuthenticationError', e.message)
  rescue DbClient::DbError => e
    puts "Database error: #{e.message}"
    ResponseHelper.error(500, 'DatabaseError', 'Failed to retrieve user profile')
  rescue StandardError => e
    puts "Unexpected error: #{e.message}"
    puts e.backtrace.join("\n")
    ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
  end
end
