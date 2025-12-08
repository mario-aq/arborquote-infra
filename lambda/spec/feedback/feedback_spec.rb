require 'spec_helper'
require_relative '../../feedback/handler'

RSpec.describe 'Feedback Lambda Handler' do
  let(:mock_event) do
    {
      'headers' => {
        'Authorization' => 'Bearer mock.jwt.token'
      },
      'body' => JSON.generate({
        'message' => 'This is a test feedback message',
        'type' => 'bug'
      })
    }
  end

  let(:mock_context) { {} }

  let(:user_id) { 'test-user-123' }
  let(:user_email) { 'test@example.com' }
  let(:user_name) { 'Test User' }

  before do
    # Mock AuthHelper
    allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({
      user_id: user_id,
      email: user_email,
      name: user_name
    })

    # Mock ValidationHelper
    allow(ValidationHelper).to receive(:validate_request_size)

    # Mock DbClient
    allow(DbClient).to receive(:generate_ulid).and_return('01ARZ3NDEKTSV4RRFFQ69G5FAV')
    allow(DbClient).to receive(:current_timestamp).and_return('2024-01-01T00:00:00Z')

    # Mock SES client
    @mock_ses_client = double('SES Client')
    allow(Aws::SES::Client).to receive(:new).and_return(@mock_ses_client)
  end

  describe 'successful feedback submission' do
    it 'returns success response with feedback ID' do
      allow(@mock_ses_client).to receive(:send_email).and_return(double(message_id: 'test-message-id'))
      result = lambda_handler(event: mock_event, context: mock_context)

      expect(result[:statusCode]).to eq(200)
      response_body = JSON.parse(result[:body])
      expect(response_body['message']).to eq('Feedback submitted successfully')
      expect(response_body['feedbackId']).to eq('01ARZ3NDEKTSV4RRFFQ69G5FAV')
      expect(response_body['submittedAt']).to eq('2024-01-01T00:00:00Z')
    end

    it 'sends email with correct content' do
      expect(@mock_ses_client).to receive(:send_email) do |params|
        expect(params[:source]).to eq('feedback@arborquote.app')
        expect(params[:destination][:to_addresses]).to eq(['feedback@arborquote.app'])

        # Check email content
        expect(params[:message][:subject][:data]).to include('New Feedback: Bug')

        body_text = params[:message][:body][:text][:data]
        expect(body_text).to include('Feedback Details:')
        expect(body_text).to include('ID: 01ARZ3NDEKTSV4RRFFQ69G5FAV')
        expect(body_text).to include('Type: bug')
        expect(body_text).to include('User ID: test-user-123')
        expect(body_text).to include('User Email: test@example.com')
        expect(body_text).to include('User Name: Test User')
        expect(body_text).to include('This is a test feedback message')

        double(message_id: 'test-message-id')
      end

      lambda_handler(event: mock_event, context: mock_context)
    end

    it 'handles feedback with sentFromUrl' do
      allow(@mock_ses_client).to receive(:send_email).and_return(double(message_id: 'test-message-id'))

      event_with_url = mock_event.merge(
        'body' => JSON.generate({
          'message' => 'Feedback with URL',
          'type' => 'comment',
          'sentFromUrl' => 'https://app.arborquote.app/quotes/123'
        })
      )

      expect(@mock_ses_client).to receive(:send_email) do |params|
        body_text = params[:message][:body][:text][:data]
        expect(body_text).to include('Sent From URL: https://app.arborquote.app/quotes/123')

        body_html = params[:message][:body][:html][:data]
        expect(body_html).to include('https://app.arborquote.app/quotes/123')

        double(message_id: 'test-message-id')
      end

      lambda_handler(event: event_with_url, context: mock_context)
    end
  end

  describe 'validation errors' do
    it 'requires message field' do
      invalid_event = mock_event.merge(
        'body' => JSON.generate({
          'type' => 'bug'
        })
      )

      result = lambda_handler(event: invalid_event, context: mock_context)

      expect(result[:statusCode]).to eq(400)
      response_body = JSON.parse(result[:body])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Missing required fields')
    end

    it 'requires type field' do
      invalid_event = mock_event.merge(
        'body' => JSON.generate({
          'message' => 'Test message'
        })
      )

      result = lambda_handler(event: invalid_event, context: mock_context)

      expect(result[:statusCode]).to eq(400)
      response_body = JSON.parse(result[:body])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Missing required fields')
    end

    it 'validates feedback type enum' do
      invalid_event = mock_event.merge(
        'body' => JSON.generate({
          'message' => 'Test message',
          'type' => 'invalid_type'
        })
      )

      result = lambda_handler(event: invalid_event, context: mock_context)

      expect(result[:statusCode]).to eq(400)
      response_body = JSON.parse(result[:body])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Feedback type must be one of')
    end

    it 'validates message length' do
      long_message = 'a' * 1001
      invalid_event = mock_event.merge(
        'body' => JSON.generate({
          'message' => long_message,
          'type' => 'bug'
        })
      )

      result = lambda_handler(event: invalid_event, context: mock_context)

      expect(result[:statusCode]).to eq(400)
      response_body = JSON.parse(result[:body])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Message cannot exceed 1000 characters')
    end

    it 'validates sentFromUrl format' do
      invalid_event = mock_event.merge(
        'body' => JSON.generate({
          'message' => 'Test message',
          'type' => 'bug',
          'sentFromUrl' => 'not-a-valid-url'
        })
      )

      result = lambda_handler(event: invalid_event, context: mock_context)

      expect(result[:statusCode]).to eq(400)
      response_body = JSON.parse(result[:body])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('sentFromUrl must be a valid HTTP/HTTPS URL')
    end
  end

  describe 'authentication errors' do
    it 'handles missing authentication' do
      allow(AuthHelper).to receive(:extract_user_from_jwt).and_raise(
        AuthenticationError.new('No JWT claims found')
      )

      result = lambda_handler(event: mock_event, context: mock_context)

      expect(result[:statusCode]).to eq(401)
      response_body = JSON.parse(result[:body])
      expect(response_body['error']).to eq('AuthenticationError')
      expect(response_body['message']).to eq('No JWT claims found')
    end
  end

  describe 'JSON parsing errors' do
    it 'handles invalid JSON' do
      invalid_event = mock_event.merge('body' => 'invalid json')

      result = lambda_handler(event: invalid_event, context: mock_context)

      expect(result[:statusCode]).to eq(400)
      response_body = JSON.parse(result[:body])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to eq('Request body must be valid JSON')
    end
  end

  describe 'SES errors' do
    it 'handles SES service errors' do
      allow(@mock_ses_client).to receive(:send_email).and_raise(
        Aws::SES::Errors::ServiceError.new(nil, 'SES error')
      )

      result = lambda_handler(event: mock_event, context: mock_context)

      expect(result[:statusCode]).to eq(500)
      response_body = JSON.parse(result[:body])
      expect(response_body['error']).to eq('InternalServerError')
      expect(response_body['message']).to eq('An unexpected error occurred')
    end
  end

  describe 'feedback types' do
    ['bug', 'comment', 'question', 'complaint', 'other'].each do |feedback_type|
      it "accepts #{feedback_type} type" do
        allow(@mock_ses_client).to receive(:send_email).and_return(double(message_id: 'test-message-id'))
        event = mock_event.merge(
          'body' => JSON.generate({
            'message' => 'Test message',
            'type' => feedback_type
          })
        )

        result = lambda_handler(event: event, context: mock_context)

        expect(result[:statusCode]).to eq(200)
        response_body = JSON.parse(result[:body])
        expect(response_body['message']).to eq('Feedback submitted successfully')
      end
    end
  end
end
