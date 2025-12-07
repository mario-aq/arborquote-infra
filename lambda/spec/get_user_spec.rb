require 'spec_helper'

RSpec.describe 'GetUser Lambda Handler' do
  let(:mock_dynamodb_client) { double('Aws::DynamoDB::Client') }

  before(:all) do
    ENV['USERS_TABLE_NAME'] = 'test-users-table'
    load 'shared/db_client.rb'
    load 'shared/auth_helper.rb'
    load 'get_user/handler.rb'
  end

  before(:each) do
    DbClient.instance_variable_set(:@dynamodb_client, nil)
    allow(Aws::DynamoDB::Client).to receive(:new).and_return(mock_dynamodb_client)
    allow(mock_dynamodb_client).to receive(:get_item).and_return(double(item: existing_user))
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
      }
    }
  end

  describe 'authentication' do
    context 'with valid JWT authentication' do
      before do
        allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
      end

      it 'successfully retrieves user profile' do
        result = lambda_handler(event: mock_event, context: {})

        expect(result['statusCode']).to eq(200)
        response_body = JSON.parse(result['body'])
        expect(response_body).to include(
          'userId' => 'user_001',
          'name' => 'John Doe',
          'email' => 'john.doe@example.com',
          'phone' => '555-1234'
        )
      end

      it 'returns all user fields' do
        result = lambda_handler(event: mock_event, context: {})

        expect(result['statusCode']).to eq(200)
        response_body = JSON.parse(result['body'])
        expect(response_body).to have_key('userId')
        expect(response_body).to have_key('name')
        expect(response_body).to have_key('email')
        expect(response_body).to have_key('phone')
        expect(response_body).to have_key('address')
        expect(response_body).to have_key('companyId')
        expect(response_body).to have_key('createdAt')
        expect(response_body).to have_key('updatedAt')
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
  end

  describe 'data retrieval' do
    before do
      allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
    end

    it 'returns 404 when user does not exist' do
      allow(mock_dynamodb_client).to receive(:get_item).and_return(double(item: nil))

      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(404)
      expect(JSON.parse(result['body'])['error']).to eq('UserNotFound')
    end

    it 'handles database errors gracefully' do
      allow(mock_dynamodb_client).to receive(:get_item).and_raise(StandardError.new('Database connection failed'))

      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(500)
      expect(JSON.parse(result['body'])['error']).to eq('DatabaseError')
    end

    it 'handles empty user data gracefully' do
      minimal_user = { 'userId' => 'user_001' }
      allow(mock_dynamodb_client).to receive(:get_item).and_return(double(item: minimal_user))

      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(200)
      response_body = JSON.parse(result['body'])
      expect(response_body['userId']).to eq('user_001')
    end
  end

  describe 'response format' do
    before do
      allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
    end

    it 'returns JSON content type' do
      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(200)
      expect(result['headers']['Content-Type']).to eq('application/json')
    end

    it 'includes CORS headers' do
      result = lambda_handler(event: mock_event, context: {})

      expect(result['headers']).to include(
        'Access-Control-Allow-Origin' => '*',
        'Access-Control-Allow-Headers' => 'Content-Type',
        'Access-Control-Allow-Methods' => 'GET,OPTIONS'
      )
    end

    it 'returns user data as JSON' do
      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(200)
      response_body = JSON.parse(result['body'])
      expect(response_body).to be_a(Hash)
      expect(response_body['userId']).to eq('user_001')
    end
  end

  describe 'error handling' do
    before do
      allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
    end

    it 'handles unexpected errors' do
      allow(mock_dynamodb_client).to receive(:get_item).and_raise(RuntimeError.new('Unexpected error'))

      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(500)
      expect(JSON.parse(result['body'])['error']).to eq('InternalServerError')
    end

    it 'logs errors appropriately' do
      allow(mock_dynamodb_client).to receive(:get_item).and_raise(StandardError.new('Database error'))

      expect {
        lambda_handler(event: mock_event, context: {})
      }.to output(/Database error: Database error/).to_stdout
    end
  end

  describe 'user data variations' do
    before do
      allow(AuthHelper).to receive(:extract_user_from_jwt).and_return({ user_id: 'user_001' })
    end

    it 'handles user with all fields populated' do
      complete_user = {
        'userId' => 'user_001',
        'name' => 'Jane Smith',
        'email' => 'jane.smith@example.com',
        'phone' => '555-9876',
        'address' => '456 Oak Street, Springfield, IL 62702',
        'companyId' => 'company_002',
        'createdAt' => '2024-01-15T10:30:00Z',
        'updatedAt' => '2024-01-20T15:45:00Z'
      }
      allow(mock_dynamodb_client).to receive(:get_item).and_return(double(item: complete_user))

      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(200)
      response_body = JSON.parse(result['body'])
      expect(response_body['name']).to eq('Jane Smith')
      expect(response_body['email']).to eq('jane.smith@example.com')
      expect(response_body['phone']).to eq('555-9876')
      expect(response_body['address']).to eq('456 Oak Street, Springfield, IL 62702')
    end

    it 'handles user with minimal fields' do
      minimal_user = {
        'userId' => 'user_001',
        'name' => 'John',
        'email' => 'john@example.com'
      }
      allow(mock_dynamodb_client).to receive(:get_item).and_return(double(item: minimal_user))

      result = lambda_handler(event: mock_event, context: {})

      expect(result['statusCode']).to eq(200)
      response_body = JSON.parse(result['body'])
      expect(response_body['name']).to eq('John')
      expect(response_body['email']).to eq('john@example.com')
      expect(response_body['phone']).to be_nil
      expect(response_body['address']).to be_nil
    end
  end
end
