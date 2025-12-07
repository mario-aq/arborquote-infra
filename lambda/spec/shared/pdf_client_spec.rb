require_relative '../../shared/pdf_client'
require_relative '../spec_helper'

RSpec.describe PdfClient do
  describe '.compute_quote_content_hash' do
    let(:quote) do
      {
        'quoteId' => '01ARZ3NDEKTSV4RRFFQ69G5FAV',
        'customerName' => 'John Doe',
        'customerPhone' => '555-1234',
        'customerAddress' => '123 Oak Street',
        'status' => 'draft',
        'notes' => 'Test notes',
        'items' => [
          {
            'itemId' => '01ITEM1',
            'type' => 'tree_removal',
            'description' => 'Large oak tree',
            'diameterInInches' => 36,
            'heightInFeet' => 45,
            'riskFactors' => ['near_structure'],
            'price' => 85000
          }
        ],
        'totalPrice' => 85000,
        'createdAt' => '2025-11-29T14:30:00.123Z',
        'updatedAt' => '2025-11-29T15:00:00.456Z'
      }
    end

    it 'generates a SHA-256 hash' do
      hash = described_class.compute_quote_content_hash(quote)
      
      expect(hash).to be_a(String)
      expect(hash.length).to eq(64) # SHA-256 hex digest is 64 chars
      expect(hash).to match(/^[0-9a-f]{64}$/)
    end

    it 'generates same hash for same content' do
      hash1 = described_class.compute_quote_content_hash(quote)
      hash2 = described_class.compute_quote_content_hash(quote)
      
      expect(hash1).to eq(hash2)
    end

    it 'generates different hash when content changes' do
      hash1 = described_class.compute_quote_content_hash(quote)
      
      quote['notes'] = 'Different notes'
      hash2 = described_class.compute_quote_content_hash(quote)
      
      expect(hash1).not_to eq(hash2)
    end

    it 'ignores timestamp changes' do
      hash1 = described_class.compute_quote_content_hash(quote)

      quote['createdAt'] = '2025-12-01T10:00:00.000Z'
      quote['updatedAt'] = '2025-12-01T11:00:00.000Z'
      hash2 = described_class.compute_quote_content_hash(quote)

      expect(hash1).to eq(hash2)
    end

    it 'includes user information in hash' do
      user1 = { 'userId' => 'user1', 'name' => 'John Doe', 'email' => 'john@example.com' }
      user2 = { 'userId' => 'user1', 'name' => 'Jane Smith', 'email' => 'john@example.com' }

      hash1 = described_class.compute_quote_content_hash(quote, user1)
      hash2 = described_class.compute_quote_content_hash(quote, user2)

      expect(hash1).not_to eq(hash2)
    end

    it 'includes company information in hash' do
      company1 = { 'companyId' => 'comp1', 'name' => 'ABC Tree Service', 'email' => 'info@abc.com' }
      company2 = { 'companyId' => 'comp1', 'name' => 'XYZ Tree Service', 'email' => 'info@abc.com' }

      hash1 = described_class.compute_quote_content_hash(quote, nil, company1)
      hash2 = described_class.compute_quote_content_hash(quote, nil, company2)

      expect(hash1).not_to eq(hash2)
    end

    it 'generates same hash when user/company data is nil' do
      hash1 = described_class.compute_quote_content_hash(quote, nil, nil)
      hash2 = described_class.compute_quote_content_hash(quote)

      expect(hash1).to eq(hash2)
    end

    it 'ignores status changes' do
      hash1 = described_class.compute_quote_content_hash(quote)
      
      quote['status'] = 'sent'
      hash2 = described_class.compute_quote_content_hash(quote)
      
      expect(hash1).to eq(hash2)
      
      quote['status'] = 'accepted'
      hash3 = described_class.compute_quote_content_hash(quote)
      
      expect(hash1).to eq(hash3)
    end

    it 'ignores photos in hash calculation' do
      quote_with_photos = quote.dup
      quote_with_photos['items'][0]['photos'] = ['photo1.jpg', 'photo2.jpg']
      
      hash1 = described_class.compute_quote_content_hash(quote)
      hash2 = described_class.compute_quote_content_hash(quote_with_photos)
      
      expect(hash1).to eq(hash2)
    end

    it 'sorts items by itemId for consistency' do
      quote_reordered = quote.dup
      quote_reordered['items'] = [
        {
          'itemId' => '01ITEM2',
          'type' => 'cleanup',
          'description' => 'Cleanup',
          'price' => 20000
        },
        {
          'itemId' => '01ITEM1',
          'type' => 'tree_removal',
          'description' => 'Large oak tree',
          'price' => 85000
        }
      ]
      
      # Create original with items in different order
      quote_ordered = quote.dup
      quote_ordered['items'] = [
        {
          'itemId' => '01ITEM1',
          'type' => 'tree_removal',
          'description' => 'Large oak tree',
          'price' => 85000
        },
        {
          'itemId' => '01ITEM2',
          'type' => 'cleanup',
          'description' => 'Cleanup',
          'price' => 20000
        }
      ]
      
      hash1 = described_class.compute_quote_content_hash(quote_reordered)
      hash2 = described_class.compute_quote_content_hash(quote_ordered)
      
      expect(hash1).to eq(hash2)
    end

    it 'detects item price changes' do
      hash1 = described_class.compute_quote_content_hash(quote)
      
      quote['items'][0]['price'] = 95000
      hash2 = described_class.compute_quote_content_hash(quote)
      
      expect(hash1).not_to eq(hash2)
    end

    it 'detects item description changes' do
      hash1 = described_class.compute_quote_content_hash(quote)
      
      quote['items'][0]['description'] = 'Updated description'
      hash2 = described_class.compute_quote_content_hash(quote)
      
      expect(hash1).not_to eq(hash2)
    end

    it 'detects risk factor changes' do
      hash1 = described_class.compute_quote_content_hash(quote)
      
      quote['items'][0]['riskFactors'] = ['near_structure', 'leaning']
      hash2 = described_class.compute_quote_content_hash(quote)
      
      expect(hash1).not_to eq(hash2)
    end
  end

  describe '.generate_pdf_key' do
    it 'generates correct S3 key format' do
      key = described_class.generate_pdf_key('user_123', 'quote_456')
      
      expect(key).to eq('user_123/quote_456/arbor_quote_quote_456_en.pdf')
    end

    it 'handles ULID format' do
      key = described_class.generate_pdf_key('01USER123', '01QUOTE456')
      
      expect(key).to eq('01USER123/01QUOTE456/arbor_quote_01QUOTE456_en.pdf')
    end
  end

  describe '.generate_pdf_presigned_url' do
    let(:bucket) { 'test-bucket' }
    let(:key) { 'user_123/quote_456/arbor_quote_quote_456.pdf' }

    it 'generates a presigned URL' do
      allow_any_instance_of(Aws::S3::Presigner).to receive(:presigned_url)
        .and_return('https://test-bucket.s3.amazonaws.com/test?signature=abc')
      
      url = described_class.generate_pdf_presigned_url(bucket, key)
      
      expect(url).to include('https://')
      expect(url).to include('amazonaws.com')
    end

    it 'uses 1-hour TTL by default' do
      expect_any_instance_of(Aws::S3::Presigner).to receive(:presigned_url) do |_, method, options|
        expect(options[:expires_in]).to eq(3600) # 1 hour
        'https://test-bucket.s3.amazonaws.com/test?signature=abc'
      end
      
      described_class.generate_pdf_presigned_url(bucket, key)
    end

    it 'accepts custom TTL' do
      expect_any_instance_of(Aws::S3::Presigner).to receive(:presigned_url) do |_, method, options|
        expect(options[:expires_in]).to eq(3600)
        'https://test-bucket.s3.amazonaws.com/test?signature=abc'
      end
      
      described_class.generate_pdf_presigned_url(bucket, key, 3600)
    end
  end

  describe '.upload_pdf' do
    let(:bucket) { 'test-bucket' }
    let(:key) { 'user_123/quote_456/arbor_quote_quote_456.pdf' }
    let(:pdf_data) { '%PDF-1.4...' }

    it 'uploads PDF with correct parameters' do
      expect_any_instance_of(Aws::S3::Client).to receive(:put_object).with(
        bucket: bucket,
        key: key,
        body: pdf_data,
        content_type: 'application/pdf',
        content_disposition: 'inline'
      )
      
      described_class.upload_pdf(bucket, key, pdf_data)
    end

    it 'raises error on S3 failure' do
      allow_any_instance_of(Aws::S3::Client).to receive(:put_object)
        .and_raise(Aws::S3::Errors::ServiceError.new(nil, 'Test error'))
      
      expect {
        described_class.upload_pdf(bucket, key, pdf_data)
      }.to raise_error(RuntimeError, /Failed to upload PDF/)
    end
  end

  describe '.delete_pdf' do
    let(:bucket) { 'test-bucket' }
    let(:key) { 'user_123/quote_456/arbor_quote_quote_456.pdf' }

    it 'deletes PDF from S3' do
      expect_any_instance_of(Aws::S3::Client).to receive(:delete_object).with(
        bucket: bucket,
        key: key
      )
      
      described_class.delete_pdf(bucket, key)
    end

    it 'handles S3 errors gracefully' do
      allow_any_instance_of(Aws::S3::Client).to receive(:delete_object)
        .and_raise(Aws::S3::Errors::ServiceError.new(nil, 'Test error'))
      
      expect {
        described_class.delete_pdf(bucket, key)
      }.not_to raise_error
    end
  end

  describe '.pdf_exists?' do
    let(:bucket) { 'test-bucket' }
    let(:key) { 'user_123/quote_456/arbor_quote_quote_456.pdf' }

    it 'returns true when PDF exists' do
      allow_any_instance_of(Aws::S3::Client).to receive(:head_object)
        .and_return(true)
      
      expect(described_class.pdf_exists?(bucket, key)).to be true
    end

    it 'returns false when PDF not found' do
      allow_any_instance_of(Aws::S3::Client).to receive(:head_object)
        .and_raise(Aws::S3::Errors::NotFound.new(nil, 'Not found'))
      
      expect(described_class.pdf_exists?(bucket, key)).to be false
    end

    it 'returns false on S3 errors' do
      allow_any_instance_of(Aws::S3::Client).to receive(:head_object)
        .and_raise(Aws::S3::Errors::ServiceError.new(nil, 'Test error'))
      
      expect(described_class.pdf_exists?(bucket, key)).to be false
    end
  end
end

