require 'spec_helper'
require 'shared/db_client'

RSpec.describe 'DbClient' do
  describe '.generate_ulid' do
    it 'generates a 26 character ULID' do
      ulid = DbClient.generate_ulid
      expect(ulid.length).to eq(26)
    end

    it 'generates unique IDs' do
      ulid1 = DbClient.generate_ulid
      ulid2 = DbClient.generate_ulid
      expect(ulid1).not_to eq(ulid2)
    end

    it 'generates time-sortable IDs' do
      ulid1 = DbClient.generate_ulid
      sleep(0.01) # Small delay to ensure timestamp difference
      ulid2 = DbClient.generate_ulid
      expect(ulid2).to be > ulid1
    end
  end

  describe '.current_timestamp' do
    it 'returns an ISO 8601 timestamp' do
      timestamp = DbClient.current_timestamp
      expect(timestamp).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/)
    end
  end
end

RSpec.describe 'ValidationHelper' do
  describe '.validate_required_fields' do
    it 'raises error when fields are missing' do
      data = { 'name' => 'John' }
      expect {
        ValidationHelper.validate_required_fields(data, ['name', 'email'])
      }.to raise_error(ValidationHelper::ValidationError, /Missing required fields: email/)
    end

    it 'raises error when fields are empty strings' do
      data = { 'name' => '  ', 'email' => 'test@example.com' }
      expect {
        ValidationHelper.validate_required_fields(data, ['name', 'email'])
      }.to raise_error(ValidationHelper::ValidationError, /Missing required fields: name/)
    end

    it 'does not raise error when all fields are present' do
      data = { 'name' => 'John', 'email' => 'john@example.com' }
      expect {
        ValidationHelper.validate_required_fields(data, ['name', 'email'])
      }.not_to raise_error
    end
  end

  describe '.validate_quote_status' do
    it 'accepts valid statuses' do
      %w[draft sent accepted rejected].each do |status|
        expect {
          ValidationHelper.validate_quote_status(status)
        }.not_to raise_error
      end
    end

    it 'rejects invalid statuses' do
      expect {
        ValidationHelper.validate_quote_status('invalid')
      }.to raise_error(ValidationHelper::ValidationError, /Invalid status/)
    end
  end

  describe '.validate_item_type' do
    it 'accepts valid item types' do
      %w[tree_removal pruning stump_grinding cleanup trimming emergency_service other].each do |type|
        expect {
          ValidationHelper.validate_item_type(type)
        }.not_to raise_error
      end
    end

    it 'rejects invalid item types' do
      expect {
        ValidationHelper.validate_item_type('invalid_type')
      }.to raise_error(ValidationHelper::ValidationError, /Invalid item type/)
    end
  end

  describe '.validate_items' do
    it 'raises error when items is nil' do
      expect {
        ValidationHelper.validate_items(nil)
      }.to raise_error(ValidationHelper::ValidationError, /Items must be an array/)
    end

    it 'raises error when items is not an array' do
      expect {
        ValidationHelper.validate_items('not an array')
      }.to raise_error(ValidationHelper::ValidationError, /Items must be an array/)
    end

    it 'raises error when items array is empty' do
      expect {
        ValidationHelper.validate_items([])
      }.to raise_error(ValidationHelper::ValidationError, /must have at least one item/)
    end

    it 'validates each item in the array' do
      items = [
        { 'type' => 'tree_removal', 'description' => 'Test tree' }
      ]
      expect {
        ValidationHelper.validate_items(items)
      }.not_to raise_error
    end
  end

  describe '.validate_item' do
    it 'raises error when type is missing' do
      item = { 'description' => 'Test' }
      expect {
        ValidationHelper.validate_item(item, 0)
      }.to raise_error(ValidationHelper::ValidationError, /Item 0: Missing required field 'type'/)
    end

    it 'raises error when description is missing' do
      item = { 'type' => 'tree_removal' }
      expect {
        ValidationHelper.validate_item(item, 0)
      }.to raise_error(ValidationHelper::ValidationError, /Item 0: Missing required field 'description'/)
    end

    it 'raises error for invalid item type' do
      item = { 'type' => 'invalid', 'description' => 'Test' }
      expect {
        ValidationHelper.validate_item(item, 0)
      }.to raise_error(ValidationHelper::ValidationError, /Invalid item type/)
    end

    it 'raises error for negative price' do
      item = { 'type' => 'tree_removal', 'description' => 'Test', 'price' => -100 }
      expect {
        ValidationHelper.validate_item(item, 0)
      }.to raise_error(ValidationHelper::ValidationError, /Price must be a non-negative integer/)
    end

    it 'raises error for non-integer price' do
      item = { 'type' => 'tree_removal', 'description' => 'Test', 'price' => 'invalid' }
      expect {
        ValidationHelper.validate_item(item, 0)
      }.to raise_error(ValidationHelper::ValidationError, /Price must be a non-negative integer/)
    end

    it 'raises error for invalid diameterInInches' do
      item = { 'type' => 'tree_removal', 'description' => 'Test', 'diameterInInches' => -5 }
      expect {
        ValidationHelper.validate_item(item, 0)
      }.to raise_error(ValidationHelper::ValidationError, /diameterInInches must be a positive number/)
    end

    it 'raises error for invalid heightInFeet' do
      item = { 'type' => 'tree_removal', 'description' => 'Test', 'heightInFeet' => 0 }
      expect {
        ValidationHelper.validate_item(item, 0)
      }.to raise_error(ValidationHelper::ValidationError, /heightInFeet must be a positive number/)
    end

    it 'accepts valid item with all fields' do
      item = {
        'type' => 'tree_removal',
        'description' => 'Large oak tree',
        'diameterInInches' => 36,
        'heightInFeet' => 45,
        'riskFactors' => ['near_structure'],
        'price' => 85000,
        'photos' => []
      }
      expect {
        ValidationHelper.validate_item(item, 0)
      }.not_to raise_error
    end

    it 'accepts valid item with minimal fields' do
      item = {
        'type' => 'cleanup',
        'description' => 'Debris removal'
      }
      expect {
        ValidationHelper.validate_item(item, 0)
      }.not_to raise_error
    end
  end
end

RSpec.describe 'ItemHelper' do
  describe '.build_item' do
    it 'generates itemId for new item' do
      item_data = {
        'type' => 'tree_removal',
        'description' => 'Test tree'
      }
      item = ItemHelper.build_item(item_data)
      expect(item['itemId']).to be_a(String)
      expect(item['itemId'].length).to eq(26)
    end

    it 'sets all provided fields' do
      item_data = {
        'type' => 'tree_removal',
        'description' => 'Large oak',
        'diameterInInches' => 36,
        'heightInFeet' => 45,
        'price' => 85000
      }
      item = ItemHelper.build_item(item_data)
      expect(item['type']).to eq('tree_removal')
      expect(item['description']).to eq('Large oak')
      expect(item['diameterInInches']).to eq(36)
      expect(item['heightInFeet']).to eq(45)
      expect(item['price']).to eq(85000)
    end

    it 'defaults empty arrays for riskFactors and photos' do
      item_data = {
        'type' => 'tree_removal',
        'description' => 'Test tree'
      }
      item = ItemHelper.build_item(item_data)
      expect(item['riskFactors']).to eq([])
      expect(item['photos']).to eq([])
    end

    it 'defaults price to 0 if not provided' do
      item_data = {
        'type' => 'tree_removal',
        'description' => 'Test tree'
      }
      item = ItemHelper.build_item(item_data)
      expect(item['price']).to eq(0)
    end
  end

  describe '.calculate_total_price' do
    it 'sums prices from all items' do
      items = [
        { 'price' => 50000 },
        { 'price' => 25000 },
        { 'price' => 15000 }
      ]
      total = ItemHelper.calculate_total_price(items)
      expect(total).to eq(90000)
    end

    it 'handles items with no price (defaults to 0)' do
      items = [
        { 'price' => 50000 },
        { 'price' => nil },
        { 'price' => 15000 }
      ]
      total = ItemHelper.calculate_total_price(items)
      expect(total).to eq(65000)
    end

    it 'returns 0 for empty array' do
      total = ItemHelper.calculate_total_price([])
      expect(total).to eq(0)
    end
  end
end

RSpec.describe 'ResponseHelper' do
  describe '.success' do
    it 'returns formatted success response' do
      body = { 'message' => 'Success' }
      response = ResponseHelper.success(200, body)
      
      expect(response[:statusCode]).to eq(200)
      expect(response[:headers]['Content-Type']).to eq('application/json')
      expect(response[:headers]['Access-Control-Allow-Origin']).to eq('*')
      expect(JSON.parse(response[:body])).to eq(body)
    end
  end

  describe '.error' do
    it 'returns formatted error response' do
      response = ResponseHelper.error(400, 'ValidationError', 'Invalid input')
      
      expect(response[:statusCode]).to eq(400)
      expect(response[:headers]['Content-Type']).to eq('application/json')
      
      body = JSON.parse(response[:body])
      expect(body['error']).to eq('ValidationError')
      expect(body['message']).to eq('Invalid input')
    end
  end
end

