require 'json'
require 'aws-sdk-ses'
require_relative '../shared/auth_helper'
require_relative '../shared/db_client'

# ValidationHelper is defined in db_client.rb
include ValidationHelper

# Lambda handler for submitting user feedback
# POST /feedback
def lambda_handler(event:, context:)
  begin
    # Extract authenticated user from JWT
    user = AuthHelper.extract_user_from_jwt(event)

    # Parse request body
    body = JSON.parse(event['body'] || '{}')

    # Validate request size
    ValidationHelper.validate_request_size(event)

    # Validate required fields
    ValidationHelper.validate_required_fields(body, ['message', 'type'])

    # Get user context
    user_id = user[:user_id]
    user_email = user[:email] || 'unknown@example.com'
    user_name = user[:name] || 'Unknown User'

    # Validate feedback data
    feedback_data = validate_feedback_data(body)

    # Generate feedback ID
    feedback_id = DbClient.generate_ulid
    submitted_at = DbClient.current_timestamp

    puts "Processing feedback #{feedback_id} from user #{user_id}"

    # Send feedback email
    send_feedback_email(feedback_data, user_id, user_email, user_name, feedback_id, submitted_at)

    # Return success response
    response_data = {
      message: 'Feedback submitted successfully',
      feedbackId: feedback_id,
      submittedAt: submitted_at
    }

    puts "Feedback #{feedback_id} submitted successfully"
    ResponseHelper.success(200, response_data)

  rescue AuthenticationError => e
    puts "Authentication error: #{e.message}"
    ResponseHelper.error(401, 'AuthenticationError', e.message)
  rescue ValidationHelper::ValidationError => e
    puts "Validation error: #{e.message}"
    ResponseHelper.error(400, 'ValidationError', e.message)
  rescue JSON::ParserError => e
    puts "JSON parse error: #{e.message}"
    ResponseHelper.error(400, 'ValidationError', 'Request body must be valid JSON')
  rescue StandardError => e
    puts "Unexpected error: #{e.message}"
    puts e.backtrace.join("\n")
    ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
  end
end

# Validate feedback data
def validate_feedback_data(body)
  feedback_data = {}

  # Validate message
  message = body['message']
  if message.nil? || message.strip.empty?
    raise ValidationHelper::ValidationError.new('Message cannot be empty')
  end
  if message.length > 1000
    raise ValidationHelper::ValidationError.new('Message cannot exceed 1000 characters')
  end
  feedback_data[:message] = message.strip

  # Validate feedback type
  valid_types = ['bug', 'comment', 'question', 'complaint', 'other']
  feedback_type = body['type']
  if feedback_type.nil? || feedback_type.strip.empty?
    raise ValidationHelper::ValidationError.new('Feedback type is required')
  end
  unless valid_types.include?(feedback_type)
    raise ValidationHelper::ValidationError.new("Feedback type must be one of: #{valid_types.join(', ')}")
  end
  feedback_data[:type] = feedback_type.strip

  # Validate sentFromUrl (optional)
  sent_from_url = body['sentFromUrl']
  if sent_from_url && !sent_from_url.strip.empty?
    # Basic URL validation
    unless sent_from_url.match?(/\Ahttps?:\/\/[^\s]+\z/)
      raise ValidationHelper::ValidationError.new('sentFromUrl must be a valid HTTP/HTTPS URL')
    end
    feedback_data[:sent_from_url] = sent_from_url.strip
  else
    feedback_data[:sent_from_url] = nil
  end

  feedback_data
end

# Send feedback email via SES
def send_feedback_email(feedback_data, user_id, user_email, user_name, feedback_id, submitted_at)
  ses_client = Aws::SES::Client.new(region: ENV['AWS_REGION'] || 'us-east-1')

  # Email content
  subject = "New Feedback: #{feedback_data[:type].capitalize}"

  body_text = <<~TEXT
    New feedback received from ArborQuote app.

    Feedback Details:
    - ID: #{feedback_id}
    - Type: #{feedback_data[:type]}
    - Submitted At: #{submitted_at}
    - User ID: #{user_id}
    - User Email: #{user_email}
    - User Name: #{user_name}
    #{feedback_data[:sent_from_url] ? "- Sent From URL: #{feedback_data[:sent_from_url]}" : ""}

    Message:
    #{feedback_data[:message]}
  TEXT

  body_html = <<~HTML
    <html>
    <body>
      <h2>New Feedback Received</h2>
      <p>New feedback received from ArborQuote app.</p>

      <h3>Feedback Details:</h3>
      <ul>
        <li><strong>ID:</strong> #{feedback_id}</li>
        <li><strong>Type:</strong> #{feedback_data[:type]}</li>
        <li><strong>Submitted At:</strong> #{submitted_at}</li>
        <li><strong>User ID:</strong> #{user_id}</li>
        <li><strong>User Email:</strong> #{user_email}</li>
        <li><strong>User Name:</strong> #{user_name}</li>
        #{feedback_data[:sent_from_url] ? "<li><strong>Sent From URL:</strong> <a href=\"#{feedback_data[:sent_from_url]}\">#{feedback_data[:sent_from_url]}</a></li>" : ""}
      </ul>

      <h3>Message:</h3>
      <div style="background-color: #f5f5f5; padding: 10px; border-radius: 5px; margin: 10px 0;">
        #{feedback_data[:message].gsub("\n", "<br>")}
      </div>
    </body>
    </html>
  HTML

  # Send email
  begin
    response = ses_client.send_email({
      source: 'feedback@arborquote.app', # This will be the verified sender
      destination: {
        to_addresses: ['feedback@arborquote.app']
      },
      message: {
        subject: {
          charset: 'UTF-8',
          data: subject
        },
        body: {
          text: {
            charset: 'UTF-8',
            data: body_text
          },
          html: {
            charset: 'UTF-8',
            data: body_html
          }
        }
      }
    })

    puts "Feedback email sent successfully with message ID: #{response.message_id}"
  rescue Aws::SES::Errors::ServiceError => e
    puts "SES error: #{e.message}"
    raise "Failed to send feedback email: #{e.message}"
  end
end
