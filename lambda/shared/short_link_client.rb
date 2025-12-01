require 'digest'
require_relative 'db_client'

# Shared short link utilities for Lambda handlers
# Handles slug generation and ShortLinks table operations
module ShortLinkClient
  # Base62 alphabet (0-9, a-z, A-Z) - URL safe, no special chars
  BASE62_ALPHABET = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.freeze
  
  class << self
    # Generate deterministic 8-char slug from quoteId + locale
    # Uses SHA-256 → integer → base62 encoding → lowercase
    # Collision probability: ~1 in 62^8 = 218 trillion (essentially zero)
    def generate_slug(quote_id, locale)
      # Create deterministic hash
      hash = Digest::SHA256.hexdigest("#{quote_id}_#{locale}")
      
      # Convert first 12 hex chars to integer (48 bits = good entropy)
      number = hash[0..11].to_i(16)
      
      # Encode to base62
      slug = encode_base62(number, 8)
      
      slug.downcase # Use lowercase only for consistency and readability
    end
    
    # Encode integer to base62 with fixed length
    def encode_base62(number, length)
      result = ''
      length.times do
        result = BASE62_ALPHABET[number % 62] + result
        number /= 62
      end
      result
    end
    
    # Create or update short link in DynamoDB
    # Returns the slug for use in response
    def upsert_short_link(table_name, quote_id, locale, pdf_key)
      slug = generate_slug(quote_id, locale)
      now = DbClient.current_timestamp
      
      # Check if short link already exists
      existing = DbClient.get_item(table_name, { 'slug' => slug })
      
      if existing
        # Update existing record (only pdfKey and updatedAt, preserve presigned URL cache)
        DbClient.update_item(
          table_name,
          { 'slug' => slug },
          {
            'pdfKey' => pdf_key,
            'updatedAt' => now
          }
        )
        puts "Updated existing short link: #{slug}"
      else
        # Create new record
        DbClient.put_item(
          table_name,
          {
            'slug' => slug,
            'quoteId' => quote_id,
            'locale' => locale,
            'pdfKey' => pdf_key,
            'createdAt' => now,
            'updatedAt' => now
          }
        )
        puts "Created new short link: #{slug}"
      end
      
      slug
    end
    
    # Delete short links for a quote (both locales)
    # Used when deleting a quote to clean up associated short links
    # Returns count of deleted links
    def delete_short_links_for_quote(table_name, quote_id)
      # Query GSI to find all short links for this quote
      short_links = DbClient.query(
        table_name,
        index_name: 'quoteId-locale-index',
        key_condition_expression: '#quoteId = :quoteId',
        expression_attribute_names: { '#quoteId' => 'quoteId' },
        expression_attribute_values: { ':quoteId' => quote_id }
      )
      
      # Delete each short link
      short_links.each do |link|
        DbClient.delete_item(table_name, { 'slug' => link['slug'] })
        puts "Deleted short link: #{link['slug']} for quote: #{quote_id}"
      end
      
      short_links.length
    rescue DbClient::DbError => e
      puts "Warning: Failed to delete short links for quote #{quote_id}: #{e.message}"
      0 # Return 0 if cleanup fails (non-fatal)
    end
  end
end

