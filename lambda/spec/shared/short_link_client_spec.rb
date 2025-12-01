require_relative '../../shared/short_link_client'
require_relative '../spec_helper'

RSpec.describe ShortLinkClient do
  describe '.generate_slug' do
    it 'generates an 8-character slug' do
      slug = described_class.generate_slug('01QUOTE123', 'en')
      
      expect(slug).to be_a(String)
      expect(slug.length).to eq(8)
    end

    it 'generates lowercase alphanumeric slug' do
      slug = described_class.generate_slug('01QUOTE123', 'en')
      
      expect(slug).to match(/^[a-z0-9]{8}$/)
    end

    it 'generates same slug for same inputs' do
      slug1 = described_class.generate_slug('01QUOTE123', 'en')
      slug2 = described_class.generate_slug('01QUOTE123', 'en')
      
      expect(slug1).to eq(slug2)
    end

    it 'generates different slugs for different locales' do
      slug_en = described_class.generate_slug('01QUOTE123', 'en')
      slug_es = described_class.generate_slug('01QUOTE123', 'es')
      
      expect(slug_en).not_to eq(slug_es)
    end

    it 'generates different slugs for different quote IDs' do
      slug1 = described_class.generate_slug('01QUOTE123', 'en')
      slug2 = described_class.generate_slug('01QUOTE456', 'en')
      
      expect(slug1).not_to eq(slug2)
    end

    it 'is deterministic across multiple calls' do
      slugs = 10.times.map { described_class.generate_slug('01QUOTE789', 'en') }
      
      expect(slugs.uniq.length).to eq(1)
    end
  end

  describe '.encode_base62' do
    it 'encodes number to base62' do
      result = described_class.encode_base62(12345, 8)
      
      expect(result).to be_a(String)
      expect(result.length).to eq(8)
      expect(result).to match(/^[0-9a-zA-Z]+$/)
    end

    it 'pads to specified length' do
      result = described_class.encode_base62(1, 8)
      
      expect(result.length).to eq(8)
    end

    it 'uses base62 alphabet (0-9, a-z, A-Z)' do
      result = described_class.encode_base62(999999, 8)
      
      expect(result).to match(/^[0-9a-zA-Z]+$/)
    end

    it 'handles large numbers' do
      large_num = 281474976710655 # Max 48-bit number
      result = described_class.encode_base62(large_num, 8)
      
      expect(result.length).to eq(8)
    end
  end

  describe '.upsert_short_link' do
    let(:table_name) { 'test-short-links-table' }
    let(:quote_id) { '01QUOTE123456' }
    let(:locale) { 'en' }
    let(:pdf_key) { 'user_123/01QUOTE123456/arbor_quote_01QUOTE123456_en.pdf' }

    before do
      allow(DbClient).to receive(:current_timestamp).and_return('2025-01-01T00:00:00.000Z')
    end

    context 'when short link does not exist' do
      before do
        allow(DbClient).to receive(:get_item).and_return(nil)
        allow(DbClient).to receive(:put_item)
      end

      it 'creates new short link record' do
        expect(DbClient).to receive(:put_item) do |table, item|
          expect(table).to eq(table_name)
          expect(item['slug']).to match(/^[a-z0-9]{8}$/)
          expect(item['quoteId']).to eq(quote_id)
          expect(item['locale']).to eq(locale)
          expect(item['pdfKey']).to eq(pdf_key)
          expect(item['createdAt']).to eq('2025-01-01T00:00:00.000Z')
          expect(item['updatedAt']).to eq('2025-01-01T00:00:00.000Z')
        end

        described_class.upsert_short_link(table_name, quote_id, locale, pdf_key)
      end

      it 'returns the slug' do
        slug = described_class.upsert_short_link(table_name, quote_id, locale, pdf_key)
        
        expect(slug).to be_a(String)
        expect(slug.length).to eq(8)
      end
    end

    context 'when short link already exists' do
      let(:existing_record) do
        {
          'slug' => 'abc123de',
          'quoteId' => quote_id,
          'locale' => locale,
          'pdfKey' => 'old/path/old.pdf',
          'createdAt' => '2024-12-01T00:00:00.000Z',
          'updatedAt' => '2024-12-01T00:00:00.000Z'
        }
      end

      before do
        allow(DbClient).to receive(:get_item).and_return(existing_record)
        allow(DbClient).to receive(:update_item)
      end

      it 'updates existing record' do
        expect(DbClient).to receive(:update_item) do |table, key, updates|
          expect(table).to eq(table_name)
          expect(key['slug']).to match(/^[a-z0-9]{8}$/)
          expect(updates['pdfKey']).to eq(pdf_key)
          expect(updates['updatedAt']).to eq('2025-01-01T00:00:00.000Z')
        end

        described_class.upsert_short_link(table_name, quote_id, locale, pdf_key)
      end

      it 'returns the same slug' do
        slug = described_class.upsert_short_link(table_name, quote_id, locale, pdf_key)
        
        expect(slug).to be_a(String)
        expect(slug.length).to eq(8)
      end
    end
  end

  describe '.delete_short_links_for_quote' do
    let(:table_name) { 'test-short-links-table' }
    let(:quote_id) { '01QUOTE123456' }

    context 'when short links exist' do
      let(:short_links) do
        [
          { 'slug' => 'abc123en', 'quoteId' => quote_id, 'locale' => 'en' },
          { 'slug' => 'xyz789es', 'quoteId' => quote_id, 'locale' => 'es' }
        ]
      end

      before do
        allow(DbClient).to receive(:query).and_return(short_links)
        allow(DbClient).to receive(:delete_item)
      end

      it 'queries GSI for short links' do
        expect(DbClient).to receive(:query).with(
          table_name,
          index_name: 'quoteId-locale-index',
          key_condition_expression: '#quoteId = :quoteId',
          expression_attribute_names: { '#quoteId' => 'quoteId' },
          expression_attribute_values: { ':quoteId' => quote_id }
        )

        described_class.delete_short_links_for_quote(table_name, quote_id)
      end

      it 'deletes all short links for the quote' do
        expect(DbClient).to receive(:delete_item).with(
          table_name,
          { 'slug' => 'abc123en' }
        )
        expect(DbClient).to receive(:delete_item).with(
          table_name,
          { 'slug' => 'xyz789es' }
        )

        described_class.delete_short_links_for_quote(table_name, quote_id)
      end

      it 'returns count of deleted links' do
        count = described_class.delete_short_links_for_quote(table_name, quote_id)
        
        expect(count).to eq(2)
      end
    end

    context 'when no short links exist' do
      before do
        allow(DbClient).to receive(:query).and_return([])
      end

      it 'returns 0' do
        count = described_class.delete_short_links_for_quote(table_name, quote_id)
        
        expect(count).to eq(0)
      end
    end

    context 'when database error occurs' do
      before do
        allow(DbClient).to receive(:query).and_raise(DbClient::DbError.new('Test error'))
      end

      it 'handles error gracefully and returns 0' do
        count = described_class.delete_short_links_for_quote(table_name, quote_id)
        
        expect(count).to eq(0)
      end

      it 'does not raise error' do
        expect {
          described_class.delete_short_links_for_quote(table_name, quote_id)
        }.not_to raise_error
      end
    end
  end
end

