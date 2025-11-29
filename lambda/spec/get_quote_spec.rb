require 'spec_helper'

RSpec.describe 'GetQuote Lambda Handler' do
  let(:mock_dynamodb_client) { double('Aws::DynamoDB::Client') }
  
  before(:each) do
    DbClient.instance_variable_set(:@dynamodb_client, nil)
    allow(Aws::DynamoDB::Client).to receive(:new).and_return(mock_dynamodb_client)
    # Default stub for get_item to allow success path
    allow(mock_dynamodb_client).to receive(:get_item).and_return(
      double(item: {
        'quoteId' => 'QUOTE123',
        'userId' => 'user_001',
        'customerName' => 'John Doe',
        'status' => 'draft',
        'totalPrice' => 85000,
        'items' => [
          {
            'itemId' => 'ITEM001',
            'type' => 'tree_removal',
            'description' => 'Oak tree',
            'price' => 85000
          }
        ],
        'createdAt' => '2025-11-29T12:00:00.000Z',
        'updatedAt' => '2025-11-29T12:00:00.000Z'
      })
    )
    load 'get_quote/handler.rb'
  end

  describe 'lambda_handler' do
    context 'when quote exists' do
      let(:event) { { 'pathParameters' => { 'quoteId' => 'QUOTE123' } } }
      let(:context) { {} }

      it 'returns the quote successfully' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(200)
        body = JSON.parse(response[:body])
        expect(body['quoteId']).to eq('QUOTE123')
        expect(body['userId']).to eq('user_001')
        expect(body['customerName']).to eq('John Doe')
        expect(body['items'].length).to eq(1)
        expect(body['totalPrice']).to eq(85000)
      end

      it 'calls DynamoDB with correct parameters' do
        expect(mock_dynamodb_client).to receive(:get_item).with(
          table_name: 'test-quotes-table',
          key: { 'quoteId' => 'QUOTE123' }
        ).and_return(double(item: { 'quoteId' => 'QUOTE123', 'userId' => 'user_001' }))

        response = lambda_handler(event: event, context: context)
        expect(response[:statusCode]).to eq(200)
      end
    end

    context 'when quote does not exist' do
      let(:event) { { 'pathParameters' => { 'quoteId' => 'NONEXISTENT' } } }
      let(:context) { {} }

      it 'returns 404 error' do
        allow(mock_dynamodb_client).to receive(:get_item).and_return(
          double(item: nil)
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(404)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('QuoteNotFound')
        expect(body['message']).to include('NONEXISTENT')
      end
    end

    context 'with missing quoteId' do
      let(:event) { { 'pathParameters' => {} } }
      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
        expect(body['message']).to include('quoteId')
      end
    end

    context 'with empty quoteId' do
      let(:event) { { 'pathParameters' => { 'quoteId' => '  ' } } }
      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
      end
    end

    context 'when DynamoDB fails' do
      let(:event) { { 'pathParameters' => { 'quoteId' => 'QUOTE123' } } }
      let(:context) { {} }

      it 'returns 500 error' do
        allow(mock_dynamodb_client).to receive(:get_item).and_raise(
          Aws::DynamoDB::Errors::ServiceError.new(nil, 'DynamoDB error')
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(500)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('DatabaseError')
        expect(body['message']).to include('Failed to retrieve quote')
      end
    end

    context 'with unexpected error' do
      let(:event) { { 'pathParameters' => { 'quoteId' => 'QUOTE123' } } }
      let(:context) { {} }

      it 'returns 500 error' do
        # Force an unexpected error
        allow(mock_dynamodb_client).to receive(:get_item).and_raise(
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
