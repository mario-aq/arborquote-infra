require 'spec_helper'

RSpec.describe 'ListQuotes Lambda Handler' do
  let(:mock_dynamodb_client) { double('Aws::DynamoDB::Client') }
  
  before(:each) do
    DbClient.instance_variable_set(:@dynamodb_client, nil)
    allow(Aws::DynamoDB::Client).to receive(:new).and_return(mock_dynamodb_client)
    # Default stub for query to allow success path
    allow(mock_dynamodb_client).to receive(:query).and_return(
      double(items: [
        {
          'quoteId' => 'QUOTE001',
          'userId' => 'user_001',
          'customerName' => 'John Doe',
          'status' => 'draft',
          'totalPrice' => 85000,
          'createdAt' => '2025-11-29T12:00:00.000Z'
        },
        {
          'quoteId' => 'QUOTE002',
          'userId' => 'user_001',
          'customerName' => 'Jane Smith',
          'status' => 'sent',
          'totalPrice' => 50000,
          'createdAt' => '2025-11-28T10:00:00.000Z'
        }
      ])
    )
    load 'list_quotes/handler.rb'
  end

  describe 'lambda_handler' do
    context 'with valid userId' do
      let(:event) { { 'queryStringParameters' => { 'userId' => 'user_001' } } }
      let(:context) { {} }

      it 'returns quotes for the user' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(200)
        body = JSON.parse(response[:body])
        expect(body['quotes'].length).to eq(2)
        expect(body['count']).to eq(2)
        expect(body['userId']).to eq('user_001')
      end

      it 'sorts quotes by createdAt descending' do
        response = lambda_handler(event: event, context: context)
        
        body = JSON.parse(response[:body])
        quotes = body['quotes']
        
        expect(quotes[0]['quoteId']).to eq('QUOTE001')
        expect(quotes[1]['quoteId']).to eq('QUOTE002')
      end

      it 'calls DynamoDB with correct GSI query' do
        expect(mock_dynamodb_client).to receive(:query).with(
          hash_including(
            table_name: 'test-quotes-table',
            index_name: 'userId-index',
            key_condition_expression: '#userId = :userId',
            expression_attribute_names: { '#userId' => 'userId' },
            expression_attribute_values: { ':userId' => 'user_001' }
          )
        ).and_return(double(items: []))

        response = lambda_handler(event: event, context: context)
        expect(response[:statusCode]).to eq(200)
      end
    end

    context 'when user has no quotes' do
      let(:event) { { 'queryStringParameters' => { 'userId' => 'user_999' } } }
      let(:context) { {} }

      it 'returns empty quotes array' do
        allow(mock_dynamodb_client).to receive(:query).and_return(
          double(items: [])
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(200)
        body = JSON.parse(response[:body])
        expect(body['quotes']).to eq([])
        expect(body['count']).to eq(0)
        expect(body['userId']).to eq('user_999')
      end
    end

    context 'with missing userId' do
      let(:event) { { 'queryStringParameters' => {} } }
      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
        expect(body['message']).to include('userId')
      end
    end

    context 'with empty userId' do
      let(:event) { { 'queryStringParameters' => { 'userId' => '  ' } } }
      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
      end
    end

    context 'with null queryStringParameters' do
      let(:event) { {} }
      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
      end
    end

    context 'when DynamoDB fails' do
      let(:event) { { 'queryStringParameters' => { 'userId' => 'user_001' } } }
      let(:context) { {} }

      it 'returns 500 error' do
        allow(mock_dynamodb_client).to receive(:query).and_raise(
          Aws::DynamoDB::Errors::ServiceError.new(nil, 'DynamoDB error')
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(500)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('DatabaseError')
        expect(body['message']).to include('Failed to retrieve quotes')
      end
    end

    context 'with unexpected error' do
      let(:event) { { 'queryStringParameters' => { 'userId' => 'user_001' } } }
      let(:context) { {} }

      it 'returns 500 error' do
        # Force an unexpected error
        allow(mock_dynamodb_client).to receive(:query).and_raise(
          StandardError.new('Unexpected error')
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(500)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('InternalServerError')
        expect(body['message']).to include('unexpected error occurred')
      end
    end
  end
end
