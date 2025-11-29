require 'spec_helper'

RSpec.describe 'UpdateQuote Lambda Handler' do
  let(:mock_dynamodb_client) { double('Aws::DynamoDB::Client') }
  
  before(:each) do
    # Reset the cached client
    DbClient.instance_variable_set(:@dynamodb_client, nil)
    allow(Aws::DynamoDB::Client).to receive(:new).and_return(mock_dynamodb_client)
    
    # Load the handler fresh for each test (avoids global method conflicts)
    load 'update_quote/handler.rb'
  end
  
  let(:existing_quote) do
    {
      'quoteId' => 'EXISTING123',
      'userId' => 'user_001',
      'customerName' => 'John Doe',
      'customerPhone' => '555-1234',
      'customerAddress' => '123 Oak Street',
      'status' => 'draft',
      'items' => [
        {
          'itemId' => 'ITEM001',
          'type' => 'tree_removal',
          'description' => 'Old description',
          'price' => 50000
        }
      ],
      'totalPrice' => 50000
    }
  end
  

  describe 'lambda_handler' do
    context 'with valid update' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'body' => JSON.generate({
            'status' => 'sent',
            'notes' => 'Updated notes'
          })
        }
      end

      let(:context) { {} }

      it 'updates the quote successfully' do
        allow(mock_dynamodb_client).to receive(:get_item).and_return(
          double(item: existing_quote)
        )

        expect(mock_dynamodb_client).to receive(:update_item) do |params|
          expect(params[:table_name]).to eq('test-quotes-table')
          expect(params[:key]).to eq({ 'quoteId' => 'EXISTING123' })
          
          # Check that expression_attribute_values contains our updates
          expect(params[:expression_attribute_values].values).to include('sent')
          expect(params[:expression_attribute_values].values).to include('Updated notes')
        end.and_return(double(attributes: existing_quote.merge('status' => 'sent')))

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(200)
      end
    end

    context 'updating items' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'body' => JSON.generate({
            'items' => [
              {
                'itemId' => 'ITEM001',
                'type' => 'tree_removal',
                'description' => 'Updated description',
                'price' => 60000
              },
              {
                'type' => 'cleanup',
                'description' => 'New cleanup item',
                'price' => 15000
              }
            ]
          })
        }
      end

      let(:context) { {} }

      it 'preserves existing itemIds and generates new ones' do
        allow(mock_dynamodb_client).to receive(:get_item).and_return(
          double(item: existing_quote)
        )

        expect(mock_dynamodb_client).to receive(:update_item) do |params|
          # Extract the items from expression_attribute_values
          items_key = params[:expression_attribute_values].keys.find { |k| k.to_s.start_with?(':val') && params[:expression_attribute_values][k].is_a?(Array) }
          updated_items = params[:expression_attribute_values][items_key]
          
          # First item should preserve itemId
          expect(updated_items[0]['itemId']).to eq('ITEM001')
          
          # Second item should have new itemId
          expect(updated_items[1]['itemId']).to be_a(String)
          expect(updated_items[1]['itemId']).not_to eq('ITEM001')
        end.and_return(double(attributes: existing_quote))

        lambda_handler(event: event, context: context)
      end

      it 'recalculates totalPrice' do
        allow(mock_dynamodb_client).to receive(:get_item).and_return(
          double(item: existing_quote)
        )

        expect(mock_dynamodb_client).to receive(:update_item) do |params|
          total_key = params[:expression_attribute_values].keys.find do |k|
            val = params[:expression_attribute_values][k]
            val.is_a?(Integer) && val == 75000 # 60000 + 15000
          end
          expect(total_key).not_to be_nil
        end.and_return(double(attributes: existing_quote))

        lambda_handler(event: event, context: context)
      end
    end

    context 'with missing quoteId' do
      let(:event) do
        {
          'pathParameters' => {},
          'body' => JSON.generate({ 'status' => 'sent' })
        }
      end

      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
        expect(body['message']).to include('quoteId')
      end
    end

    context 'with empty body' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'body' => '{}'
        }
      end

      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
        expect(body['message']).to include('cannot be empty')
      end
    end

    context 'when quote does not exist' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'NONEXISTENT' },
          'body' => JSON.generate({ 'status' => 'sent' })
        }
      end

      let(:context) { {} }

      it 'returns 404 error' do
        allow(mock_dynamodb_client).to receive(:get_item).and_return(
          double(item: nil)
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(404)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('QuoteNotFound')
      end
    end

    context 'with invalid status' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'body' => JSON.generate({ 'status' => 'invalid_status' })
        }
      end

      let(:context) { {} }

      it 'returns 400 error' do
        allow(mock_dynamodb_client).to receive(:get_item).and_return(
          double(item: existing_quote)
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
        expect(body['message']).to include('Invalid status')
      end
    end

    context 'with invalid items' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'body' => JSON.generate({
            'items' => [
              {
                'type' => 'invalid_type',
                'description' => 'Test'
              }
            ]
          })
        }
      end

      let(:context) { {} }

      it 'returns 400 error' do
        allow(mock_dynamodb_client).to receive(:get_item).and_return(
          double(item: existing_quote)
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
      end
    end

    context 'with invalid JSON' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'body' => 'invalid json'
        }
      end

      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('InvalidJSON')
      end
    end

    context 'when DynamoDB get_item fails' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'body' => JSON.generate({ 'status' => 'sent' })
        }
      end

      let(:context) { {} }

      it 'returns 500 error' do
        allow(mock_dynamodb_client).to receive(:get_item).and_raise(
          Aws::DynamoDB::Errors::ServiceError.new(nil, 'DynamoDB error')
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(500)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('DatabaseError')
      end
    end

    context 'when DynamoDB update_item fails' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'body' => JSON.generate({ 'status' => 'sent' })
        }
      end

      let(:context) { {} }

      it 'returns 500 error' do
        allow(mock_dynamodb_client).to receive(:get_item).and_return(
          double(item: existing_quote)
        )
        allow(mock_dynamodb_client).to receive(:update_item).and_raise(
          Aws::DynamoDB::Errors::ServiceError.new(nil, 'DynamoDB error')
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(500)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('DatabaseError')
      end
    end
  end
end

