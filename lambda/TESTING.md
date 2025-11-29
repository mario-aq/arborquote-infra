# Testing Guide

This document explains how to run and write tests for ArborQuote Lambda functions.

## Setup

### Prerequisites

- **Ruby 3.2+** installed
- **Bundler** gem manager

### Install Test Dependencies

```bash
cd lambda
bundle install
```

This installs:
- `rspec` - Testing framework
- `simplecov` - Code coverage
- `aws-sdk-dynamodb` - AWS SDK (for mocking)

## Running Tests

### Run All Tests

```bash
cd lambda
bundle exec rspec
```

Or use the test script:

```bash
cd lambda
chmod +x run_tests.sh
./run_tests.sh
```

### Run Specific Test Files

```bash
# Test create_quote handler
bundle exec rspec spec/create_quote_spec.rb

# Test shared utilities
bundle exec rspec spec/shared/db_client_spec.rb

# Test all handlers
bundle exec rspec spec/*_spec.rb
```

### Run Tests with Coverage

Coverage is automatically generated when running tests. After running, open:

```bash
open coverage/index.html
```

Target: **80% minimum coverage**

### Run Tests in Watch Mode

```bash
bundle exec guard
```

(Requires installing guard-rspec)

## Test Structure

```
lambda/
├── spec/
│   ├── spec_helper.rb              # RSpec configuration
│   ├── shared/
│   │   └── db_client_spec.rb       # Shared utilities tests
│   ├── create_quote_spec.rb        # Create quote handler tests
│   ├── update_quote_spec.rb        # Update quote handler tests
│   ├── get_quote_spec.rb           # Get quote handler tests
│   └── list_quotes_spec.rb         # List quotes handler tests
├── Gemfile                         # Ruby dependencies
├── .rspec                          # RSpec config
└── run_tests.sh                    # Test runner script
```

## What's Tested

### Shared Utilities (`spec/shared/db_client_spec.rb`)

- ✅ ULID generation (uniqueness, time-sortability)
- ✅ Timestamp formatting (ISO 8601)
- ✅ Field validation (required fields, empty values)
- ✅ Status validation (valid/invalid statuses)
- ✅ Item type validation (valid/invalid types)
- ✅ Item validation (type, description, price, dimensions)
- ✅ Items array validation (empty array, missing items)
- ✅ Total price calculation
- ✅ Response formatting (success/error)

### Create Quote Handler (`spec/create_quote_spec.rb`)

- ✅ Successfully creates quote with valid input
- ✅ Generates unique itemIds
- ✅ Auto-calculates totalPrice from items
- ✅ Uses custom status if provided
- ✅ Returns 400 for missing required fields
- ✅ Returns 400 for empty items array
- ✅ Returns 400 for invalid item type
- ✅ Returns 400 for invalid JSON
- ✅ Returns 400 for invalid status
- ✅ Returns 500 when DynamoDB fails

### Update Quote Handler (`spec/update_quote_spec.rb`)

- ✅ Successfully updates quote fields
- ✅ Updates items and recalculates totalPrice
- ✅ Preserves existing itemIds
- ✅ Generates new itemIds for new items
- ✅ Returns 400 for missing quoteId
- ✅ Returns 400 for empty body
- ✅ Returns 404 when quote doesn't exist
- ✅ Returns 400 for invalid status
- ✅ Returns 400 for invalid items
- ✅ Returns 400 for invalid JSON
- ✅ Returns 500 when DynamoDB fails (get or update)

### Get Quote Handler (`spec/get_quote_spec.rb`)

- ✅ Successfully retrieves quote
- ✅ Calls DynamoDB with correct parameters
- ✅ Returns 404 when quote doesn't exist
- ✅ Returns 400 for missing quoteId
- ✅ Returns 400 for empty quoteId
- ✅ Returns 500 when DynamoDB fails

### List Quotes Handler (`spec/list_quotes_spec.rb`)

- ✅ Successfully lists quotes for user
- ✅ Sorts quotes by createdAt (descending)
- ✅ Calls DynamoDB with correct GSI query
- ✅ Returns empty array when user has no quotes
- ✅ Returns 400 for missing userId
- ✅ Returns 400 for empty userId
- ✅ Returns 400 for null queryStringParameters
- ✅ Returns 500 when DynamoDB fails

## Writing Tests

### Test Structure Example

```ruby
require 'spec_helper'
require 'your_handler/handler'

RSpec.describe 'YourHandler Lambda' do
  let(:mock_dynamodb_client) { double('Aws::DynamoDB::Client') }
  
  before do
    allow(Aws::DynamoDB::Client).to receive(:new).and_return(mock_dynamodb_client)
  end

  describe 'lambda_handler' do
    context 'with valid input' do
      let(:event) { { 'body' => JSON.generate({ 'key' => 'value' }) } }
      let(:context) { {} }

      it 'does something' do
        # Setup mock
        allow(mock_dynamodb_client).to receive(:some_method).and_return(some_value)
        
        # Call handler
        response = lambda_handler(event: event, context: context)
        
        # Assert
        expect(response[:statusCode]).to eq(200)
      end
    end
  end
end
```

### Best Practices

1. **Mock External Dependencies**
   - Always mock DynamoDB client
   - Don't make real AWS API calls in tests

2. **Test Happy Path and Error Cases**
   - Valid input → Success
   - Invalid input → Proper error
   - External failure → Graceful error

3. **Use Descriptive Context Blocks**
   ```ruby
   context 'when user exists' do
   context 'with invalid email' do
   context 'when DynamoDB fails' do
   ```

4. **Test One Thing Per Example**
   ```ruby
   it 'generates unique itemIds' do
     # Test only itemId uniqueness
   end
   
   it 'calculates totalPrice' do
     # Test only totalPrice calculation
   end
   ```

5. **Use Let for Test Data**
   ```ruby
   let(:valid_quote) { { 'quoteId' => '123', ... } }
   let(:event) { { 'body' => JSON.generate(valid_quote) } }
   ```

## Code Coverage

SimpleCov tracks code coverage and generates reports:

- **Minimum Coverage:** 80%
- **Report Location:** `lambda/coverage/index.html`
- **Console Output:** Shows coverage summary after tests

### View Coverage Report

```bash
cd lambda
bundle exec rspec
open coverage/index.html
```

## Continuous Integration

To run tests in CI/CD:

```yaml
# .github/workflows/test.yml (example)
- name: Install Ruby dependencies
  run: |
    cd lambda
    bundle install

- name: Run tests
  run: |
    cd lambda
    bundle exec rspec

- name: Check coverage
  run: |
    cd lambda
    bundle exec rspec --format progress
```

## Troubleshooting

### "Bundle install fails"

```bash
# Use system gems instead of vendor/bundle
bundle install --system
```

### "Tests are slow"

- RSpec runs tests in random order by default
- Each test mocks DynamoDB, so no real API calls

### "Coverage report not generated"

```bash
# Make sure simplecov gems are installed
bundle install
bundle exec rspec
```

### "Ruby version mismatch"

```bash
# Check Ruby version
ruby --version  # Should be 3.2+

# Use rbenv or rvm to switch versions
rbenv install 3.2.0
rbenv local 3.2.0
```

## Next Steps

1. Run tests: `cd lambda && bundle exec rspec`
2. Check coverage: `open coverage/index.html`
3. Add tests for new handlers as you build features
4. Keep coverage above 80%

## Resources

- [RSpec Documentation](https://rspec.info/)
- [SimpleCov Coverage Tool](https://github.com/simplecov-ruby/simplecov)
- [AWS SDK for Ruby - Mocking](https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/stubbing.html)

