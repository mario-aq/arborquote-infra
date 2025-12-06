require 'spec_helper'

RSpec.describe 'UpdateQuote Lambda Handler' do
  let(:mock_dynamodb_client) { double('Aws::DynamoDB::Client') }

  before(:all) do
    ENV['QUOTES_TABLE'] = 'test-quotes-table'
    ENV['PHOTOS_BUCKET_NAME'] = 'test-photos-bucket'
    load 'shared/db_client.rb'
    load 'shared/s3_client.rb'
    load 'shared/auth_helper.rb'
    load 'update_quote/handler.rb'
  end

  before(:each) do
    DbClient.instance_variable_set(:@dynamodb_client, nil)
    allow(Aws::DynamoDB::Client).to receive(:new).and_return(mock_dynamodb_client)
    allow(mock_dynamodb_client).to receive(:put_item)
    allow(mock_dynamodb_client).to receive(:get_item).and_return(double(item: existing_quote))
    allow(mock_dynamodb_client).to receive(:update_item).and_return(double(attributes: updated_quote))

    # Mock S3 operations to avoid XML library errors
    allow(S3Client).to receive(:delete_item_photos).and_return(nil)
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
          'description' => 'Large oak tree removal',
          'price' => 50000
        }
      ],
      'totalPrice' => 50000,
      'createdAt' => '2024-01-01T00:00:00Z',
      'updatedAt' => '2024-01-01T00:00:00Z'
    }
  end

  let(:updated_quote) do
    existing_quote.merge(
      'updatedAt' => '2024-01-02T00:00:00Z',
      'items' => [
        {
          'itemId' => 'ITEM001',
          'type' => 'tree_removal',
          'description' => 'Large oak tree',
          'diameterInInches' => 36,
          'heightInFeet' => 45,
          'riskFactors' => ['near_structure'],
          'price' => 85000
        },
        {
          'itemId' => 'ITEM002',
          'type' => 'stump_grinding',
          'description' => 'Grind stump',
          'price' => 25000
        }
      ],
      'totalPrice' => 110000
    )
  end

  describe 'lambda_handler' do
    context 'with valid JWT authentication' do
      let(:event) do
        {
          'requestContext' => {
            'authorizer' => {
              'jwt' => {
                'claims' => {
                  'sub' => 'user_001',
                  'cognito:username' => 'testuser',
                  'email' => 'test@example.com'
                }
              }
            }
          },
          'body' => JSON.generate({
            'customerName' => 'John Doe',
            'customerPhone' => '555-1234',
            'customerAddress' => '123 Oak Street',
            'items' => [
              {
                'type' => 'tree_removal',
                'description' => 'Large oak tree',
                'diameterInInches' => 36,
                'heightInFeet' => 45,
                'riskFactors' => ['near_structure'],
                'price' => 85000
              },
              {
                'type' => 'stump_grinding',
                'description' => 'Grind stump',
                'price' => 25000
              }
            ],
            'notes' => 'Customer wants work before winter'
          })
        }
      end

      let(:context) { {} }

      it 'creates a quote successfully' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(200)
        body = JSON.parse(response[:body])
        expect(body['userId']).to eq('user_001')
        expect(body['totalPrice']).to eq(110000)
        expect(body['items'].length).to eq(2)
        expect(body['status']).to eq('draft')
        expect(body['quoteId']).to be_a(String)
        expect(body['createdAt']).to match(/^\d{4}-\d{2}-\d{2}T/)
      end

      it 'generates unique itemIds for each item' do
        response = lambda_handler(event: event, context: context)
        body = JSON.parse(response[:body])
        item_ids = body['items'].map { |item| item['itemId'] }
        expect(item_ids.uniq.length).to eq(item_ids.length)
      end

      it 'auto-calculates totalPrice from items' do
        response = lambda_handler(event: event, context: context)
        body = JSON.parse(response[:body])
        expect(body['totalPrice']).to eq(110000)
      end
    end

    context 'with custom status' do
      let(:event) do
        {
          'requestContext' => {
            'authorizer' => {
              'jwt' => {
                'claims' => {
                  'sub' => 'user_001',
                  'cognito:username' => 'testuser'
                }
              }
            }
          },
          'body' => JSON.generate({
            'customerName' => 'John Doe',
            'customerPhone' => '555-1234',
            'customerAddress' => '123 Oak Street',
            'status' => 'sent',
            'items' => [
              {
                'type' => 'tree_removal',
                'description' => 'Test tree',
                'price' => 50000
              }
            ]
          })
        }
      end

      let(:context) { {} }

      it 'uses provided status' do
        response = lambda_handler(event: event, context: context)
        body = JSON.parse(response[:body])
        expect(body['status']).to eq('sent')
      end
    end

    context 'with missing required fields' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'requestContext' => {
            'authorizer' => {
              'jwt' => {
                'claims' => {
                  'sub' => 'user_001',
                  'cognito:username' => 'testuser'
                }
              }
            }
          },
          'body' => JSON.generate({})
        }
      end

      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
        expect(body['message']).to include('Request body cannot be empty')
      end
    end

    context 'with empty items array' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'requestContext' => {
            'authorizer' => {
              'jwt' => {
                'claims' => {
                  'sub' => 'user_001',
                  'cognito:username' => 'testuser'
                }
              }
            }
          },
          'body' => JSON.generate({
            'customerName' => 'John Doe',
            'customerPhone' => '555-1234',
            'customerAddress' => '123 Oak Street',
            'items' => []
          })
        }
      end

      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
        expect(body['message']).to include('must have at least one item')
      end
    end

    context 'with invalid item type' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'requestContext' => {
            'authorizer' => {
              'jwt' => {
                'claims' => {
                  'sub' => 'user_001',
                  'cognito:username' => 'testuser'
                }
              }
            }
          },
          'body' => JSON.generate({
            'customerName' => 'John Doe',
            'customerPhone' => '555-1234',
            'customerAddress' => '123 Oak Street',
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
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
        expect(body['message']).to include('Invalid item type')
      end
    end

    context 'with invalid JSON' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'requestContext' => {
            'authorizer' => {
              'jwt' => {
                'claims' => {
                  'sub' => 'user_001',
                  'cognito:username' => 'testuser'
                }
              }
            }
          },
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

    context 'with invalid status' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'requestContext' => {
            'authorizer' => {
              'jwt' => {
                'claims' => {
                  'sub' => 'user_001',
                  'cognito:username' => 'testuser'
                }
              }
            }
          },
          'body' => JSON.generate({
            'customerName' => 'John Doe',
            'customerPhone' => '555-1234',
            'customerAddress' => '123 Oak Street',
            'status' => 'invalid_status',
            'items' => [
              {
                'type' => 'tree_removal',
                'description' => 'Test tree'
              }
            ]
          })
        }
      end

      let(:context) { {} }

      it 'returns 400 error' do
        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(400)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('ValidationError')
        expect(body['message']).to include('Invalid status')
      end
    end

    context 'when DynamoDB fails' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'requestContext' => {
            'authorizer' => {
              'jwt' => {
                'claims' => {
                  'sub' => 'user_001',
                  'cognito:username' => 'testuser'
                }
              }
            }
          },
          'body' => JSON.generate({
            'customerName' => 'John Doe',
            'customerPhone' => '555-1234',
            'customerAddress' => '123 Oak Street',
            'items' => [
              {
                'type' => 'tree_removal',
                'description' => 'Test tree',
                'price' => 50000
              }
            ]
          })
        }
      end

      let(:context) { {} }

      it 'returns 500 error' do
        allow(mock_dynamodb_client).to receive(:update_item).and_raise(
          Aws::DynamoDB::Errors::ServiceError.new(nil, 'DynamoDB error')
        )

        response = lambda_handler(event: event, context: context)
        
        expect(response[:statusCode]).to eq(500)
        body = JSON.parse(response[:body])
        expect(body['error']).to eq('DatabaseError')
        expect(body['message']).to include('Failed to update quote')
      end
    end

    context 'with unexpected error' do
      let(:event) do
        {
          'pathParameters' => { 'quoteId' => 'EXISTING123' },
          'requestContext' => {
            'authorizer' => {
              'jwt' => {
                'claims' => {
                  'sub' => 'user_001',
                  'cognito:username' => 'testuser'
                }
              }
            }
          },
          'body' => JSON.generate({
            'customerName' => 'John Doe',
            'customerPhone' => '555-1234',
            'customerAddress' => '123 Oak Street',
            'items' => [
              {
                'type' => 'tree_removal',
                'description' => 'Test tree'
              }
            ]
          })
        }
      end

      let(:context) { {} }

      it 'returns 500 error and logs backtrace' do
        # Force an unexpected error after validation
        allow(DbClient).to receive(:generate_ulid).and_raise(
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
