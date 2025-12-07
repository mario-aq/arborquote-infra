require 'spec_helper'

RSpec.describe 'UpdateUser Lambda Handler' do
  let(:mock_dynamodb_client) { double('Aws::DynamoDB::Client') }

  before(:all) do
    ENV['USERS_TABLE_NAME'] = 'test-users-table'
    load 'shared/db_client.rb'
    load 'shared/auth_helper.rb'
    load 'update_user/handler.rb'
  end

  before(:each) do
    DbClient.instance_variable_set(:@dynamodb_client, nil)
    allow(Aws::DynamoDB::Client).to receive(:new).and_return(mock_dynamodb_client)
    allow(mock_dynamodb_client).to receive(:get_item).and_return(double(item: existing_user))
    allow(mock_dynamodb_client).to receive(:update_item).and_return(double(attributes: updated_attributes))
  end

  let(:existing_user) do
    {
      'userId' => 'user_001',
      'name' => 'John Doe',
      'email' => 'john.doe@example.com',
      'phone' => '555-1234',
      'address' => '123 Main St',
      'companyId' => 'company_001',
      'createdAt' => '2024-01-01T00:00:00Z',
      'updatedAt' => '2024-01-01T00:00:00Z'
    }
  end

  let(:updated_attributes) do
    {
      'name' => ['John Smith'],
      'email' => ['john.smith@example.com'],
      'phone' => ['555-9876'],
      'updatedAt' => ['2024-01-02T00:00:00Z']
    }
  end

  let(:valid_jwt_payload) do
    {
      'sub' => 'user_001',
      'email' => 'john.doe@example.com',
      'cognito:username' => 'user_001'
    }
  end

  let(:mock_event) do
    {
      'headers' => {
        'authorization' => 'Bearer valid.jwt.token'
      },
      'body' => '{"name":"John Smith","email":"john.smith@example.com","phone":"555-9876"}'
    }
  end

  describe 'authentication and authorization' do
    context 'with valid JWT authentication' do
      before do
        allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
        allow(AuthHelper).to receive(:validate_resource_ownership).and_return(nil)
      end

      it 'successfully updates user profile' do
        result = lambda_handler(event: mock_event, context: {})

        expect(result['statusCode']).to eq(200)
        expect(JSON.parse(result['body'])).to include(
          'userId' => 'user_001',
          'name' => 'John Smith',
          'email' => 'john.smith@example.com',
          'phone' => '555-9876'
        )
      end

      it 'allows partial updates' do
        partial_event = mock_event.merge('body' => '{"name":"John Smith"}')
        result = lambda_handler(event: partial_event, context: {})

        expect(result['statusCode']).to eq(200)
        expect(JSON.parse(result['body'])).to include('name' => 'John Smith')
      end

      it 'validates email format' do
        invalid_email_event = mock_event.merge('body' => '{"email":"invalid-email"}')
        result = lambda_handler(event: invalid_email_event, context: {})

        expect(result['statusCode']).to eq(400)
        expect(JSON.parse(result['body'])['error']).to eq('ValidationError')
      end

      it 'validates phone number length' do
        invalid_phone_event = mock_event.merge('body' => '{"phone":"123"}')
        result = lambda_handler(event: invalid_phone_event, context: {})

        expect(result['statusCode']).to eq(400)
        expect(JSON.parse(result['body'])['error']).to eq('ValidationError')
      end

      it 'requires at least one field to update' do
        empty_update_event = mock_event.merge('body' => '{}')
        result = lambda_handler(event: empty_update_event, context: {})

        expect(result['statusCode']).to eq(400)
        expect(JSON.parse(result['body'])['error']).to eq('ValidationError')
      end
    end

    context 'with invalid authentication' do
      it 'returns 401 for missing JWT' do
        allow(AuthHelper).to receive(:extract_user_from_jwt).and_raise(AuthenticationError.new('No JWT claims found'))

        result = lambda_handler(event: mock_event.merge('headers' => {}), context: {})

        expect(result['statusCode']).to eq(401)
        expect(JSON.parse(result['body'])['error']).to eq('AuthenticationError')
      end

      it 'returns 401 for invalid JWT' do
        allow(AuthHelper).to receive(:extract_user_from_jwt).and_raise(AuthenticationError.new('Invalid JWT token'))

        result = lambda_handler(event: mock_event, context: {})

        expect(result['statusCode']).to eq(401)
        expect(JSON.parse(result['body'])['error']).to eq('AuthenticationError')
      end
    end

    context 'with authorization issues' do
      before do
        allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
      end

      it 'returns 404 when user does not exist' do
        allow(mock_dynamodb_client).to receive(:get_item).and_return(double(item: nil))

        result = lambda_handler(event: mock_event, context: {})

        expect(result['statusCode']).to eq(404)
        expect(JSON.parse(result['body'])['error']).to eq('UserNotFound')
      end

      it 'prevents users from updating other users profiles' do
        allow(AuthHelper).to receive(:validate_resource_ownership).and_raise(AuthorizationError.new('Access denied'))

        result = lambda_handler(event: mock_event, context: {})

        expect(result['statusCode']).to eq(403)
        expect(JSON.parse(result['body'])['error']).to eq('AuthorizationError')
      end
    end
  end

  describe 'input validation' do
    before do
      allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
      allow(AuthHelper).to receive(:validate_resource_ownership).and_return(nil)
    end

    it 'validates name cannot be empty' do
      invalid_name_event = mock_event.merge('body' => '{"name":""}')
      result = lambda_handler(event: invalid_name_event, context: {})

      expect(result['statusCode']).to eq(400)
      expect(JSON.parse(result['body'])['message']).to include('cannot be empty')
    end

    it 'validates email cannot be empty' do
      invalid_email_event = mock_event.merge('body' => '{"email":""}')
      result = lambda_handler(event: invalid_email_event, context: {})

      expect(result['statusCode']).to eq(400)
      expect(JSON.parse(result['body'])['message']).to include('cannot be empty')
    end

    it 'accepts valid email formats' do
      valid_emails = ['test@example.com', 'user.name@domain.co.uk', 'user+tag@example.com']
      valid_emails.each do |email|
        valid_email_event = mock_event.merge('body' => "{\"email\":\"#{email}\"}")
        result = lambda_handler(event: valid_email_event, context: {})

        expect(result['statusCode']).to eq(200)
      end
    end

    it 'handles invalid JSON' do
      invalid_json_event = mock_event.merge('body' => 'invalid json')
      result = lambda_handler(event: invalid_json_event, context: {})

      expect(result['statusCode']).to eq(400)
      expect(JSON.parse(result['body'])['error']).to eq('ValidationError')
    end

    it 'strips whitespace from string fields' do
      whitespace_event = mock_event.merge('body' => '{"name":"  John Smith  ","email":" john@example.com ","phone":" 555-1234 "}')

      result = lambda_handler(event: whitespace_event, context: {})

      response_body = JSON.parse(result['body'])
      expect(response_body['name']).to eq('John Smith')
      expect(response_body['email']).to eq('john@example.com')
      expect(response_body['phone']).to eq('555-1234')
    end

    it 'lowercases email addresses' do
      uppercase_email_event = mock_event.merge('body' => '{"email":"JOHN@EXAMPLE.COM"}')

      result = lambda_handler(event: uppercase_email_event, context: {})

      expect(JSON.parse(result['body'])['email']).to eq('john@example.com')
    end
  end

  describe 'database operations' do
    before do
      allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
      allow(AuthHelper).to receive(:validate_resource_ownership).and_return(nil)
    end

    it 'handles database errors gracefully' do
      allow(mock_dynamodb_client).to receive(:get_item).and_raise(StandardError.new('Database connection failed'))

      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(500)
      expect(JSON.parse(result['body'])['error']).to eq('DatabaseError')
    end

    it 'handles update errors gracefully' do
      allow(mock_dynamodb_client).to receive(:update_item).and_raise(StandardError.new('Update failed'))

      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(500)
      expect(JSON.parse(result['body'])['error']).to eq('DatabaseError')
    end

    it 'updates the updatedAt timestamp' do
      allow(mock_dynamodb_client).to receive(:update_item) do |table, key, updates|
        expect(updates).to include('updatedAt')
        double(attributes: updated_attributes)
      end

      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(200)
    end
  end

  describe 'edge cases' do
    before do
      allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
      allow(AuthHelper).to receive(:validate_resource_ownership).and_return(nil)
    end

    it 'handles empty address field' do
      address_event = mock_event.merge('body' => '{"address":""}')
      result = lambda_handler(event: address_event, context: {})

      expect(result['statusCode']).to eq(200)
      # Empty address should not be included in update
      expect(JSON.parse(result['body'])['address']).to eq('123 Main St') # original value
    end

    it 'handles nil values in request' do
      nil_value_event = mock_event.merge('body' => '{"name":null,"email":null}')
      result = lambda_handler(event: nil_value_event, context: {})

      expect(result['statusCode']).to eq(400)
      expect(JSON.parse(result['body'])['error']).to eq('ValidationError')
    end

    it 'handles very long names' do
      long_name = 'A' * 200
      long_name_event = mock_event.merge('body' => "{\"name\":\"#{long_name}\"}")
      result = lambda_handler(event: long_name_event, context: {})

      expect(result['statusCode']).to eq(200)
      expect(JSON.parse(result['body'])['name']).to eq(long_name)
    end

    it 'handles special characters in address' do
      special_address = '123 Main St, Apt #5, City, ST 12345-6789'
      address_event = mock_event.merge('body' => "{\"address\":\"#{special_address}\"}")
      result = lambda_handler(event: address_event, context: {})

      expect(result['statusCode']).to eq(200)
      expect(JSON.parse(result['body'])['address']).to eq(special_address)
    end
  end

  describe 'response format' do
    before do
      allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
      allow(AuthHelper).to receive(:validate_resource_ownership).and_return(nil)
    end

    it 'returns complete user object with updated fields' do
      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(200)
      expect(result['headers']['Content-Type']).to eq('application/json')

      response_body = JSON.parse(result['body'])
      expect(response_body).to include(
        'userId' => 'user_001',
        'name' => 'John Smith',
        'email' => 'john.smith@example.com',
        'phone' => '555-9876'
      )
      expect(response_body).to include('companyId', 'createdAt', 'updatedAt')
    end

    it 'includes CORS headers' do
      result = lambda_handler(event: mock_event, context: {})

      expect(result['headers']).to include(
        'Access-Control-Allow-Origin' => '*',
        'Access-Control-Allow-Headers' => 'Content-Type',
        'Access-Control-Allow-Methods' => 'PUT,OPTIONS'
      )
    end
  end
end
