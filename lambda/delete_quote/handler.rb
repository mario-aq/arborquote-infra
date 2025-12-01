require 'json'
require 'date'
require_relative '../shared/db_client'
require_relative '../shared/s3_client'
require_relative '../shared/pdf_client'
require_relative '../shared/short_link_client'

# Lambda handler for deleting a quote
# DELETE /quotes/{quoteId}
def lambda_handler(event:, context:)
  puts "Event: #{JSON.generate(event)}"

  # Get quoteId from path parameters
  path_params = event['pathParameters'] || {}
  quote_id = path_params['quoteId']
  
  if quote_id.nil? || quote_id.strip.empty?
    return ResponseHelper.error(400, 'ValidationError', 'quoteId path parameter is required')
  end
  
  # Check if quote exists first
  quotes_table = ENV['QUOTES_TABLE_NAME']
  existing_quote = DbClient.get_item(
    quotes_table,
    { 'quoteId' => quote_id }
  )
  
  if existing_quote.nil?
    puts "Quote not found: #{quote_id}"
    return ResponseHelper.error(404, 'QuoteNotFound', "Quote with ID #{quote_id} not found")
  end
  
  # Delete all photos from S3 for this quote
  bucket_name = ENV['PHOTOS_BUCKET_NAME']
  user_id = existing_quote['userId']
  created_at = existing_quote['createdAt']
  items = existing_quote['items'] || []
  
  if !items.empty?
    # Parse date for S3 prefix
    date = DateTime.parse(created_at)
    year = date.year
    month = date.month.to_s.rjust(2, '0')
    day = date.day.to_s.rjust(2, '0')
    
    # Delete all photos for each item
    items.each do |item|
      if item['photos'] && !item['photos'].empty?
        # Delete all photos for this item using itemId
        prefix = "#{year}/#{month}/#{day}/#{user_id}/#{quote_id}/#{item['itemId']}/"
        S3Client.delete_item_photos(bucket_name, prefix)
        puts "Deleted #{item['photos'].length} photo(s) for item #{item['itemId']} at prefix: #{prefix}"
      end
    end
    
    puts "Deleted all photos for quote: #{quote_id}"
  else
    puts "No items/photos to delete for quote: #{quote_id}"
  end
  
  # Delete PDFs from S3 if they exist (both locales)
  pdf_bucket = ENV['PDF_BUCKET_NAME']
  ['pdfS3KeyEn', 'pdfS3KeyEs'].each do |key_field|
    if existing_quote[key_field]
      pdf_key = existing_quote[key_field]
      puts "Deleting PDF (#{key_field}): #{pdf_key}"
      PdfClient.delete_pdf(pdf_bucket, pdf_key)
    end
  end
  
  # Also check for legacy pdfS3Key (for backwards compatibility)
  if existing_quote['pdfS3Key']
    pdf_key = existing_quote['pdfS3Key']
    puts "Deleting legacy PDF: #{pdf_key}"
    PdfClient.delete_pdf(pdf_bucket, pdf_key)
  end
  
  puts "Deleted all PDFs for quote: #{quote_id}"
  
  # Delete short links for this quote (both locales)
  short_links_table = ENV['SHORT_LINKS_TABLE_NAME']
  if short_links_table
    begin
      deleted_count = ShortLinkClient.delete_short_links_for_quote(
        short_links_table,
        quote_id
      )
      puts "Deleted #{deleted_count} short link(s) for quote: #{quote_id}"
    rescue StandardError => e
      puts "Warning: Failed to delete short links: #{e.message}"
      # Non-fatal - continue with quote deletion
    end
  else
    puts "Warning: SHORT_LINKS_TABLE_NAME not set, skipping short link cleanup"
  end
  
  # Delete quote from DynamoDB
  DbClient.delete_item(
    quotes_table,
    { 'quoteId' => quote_id }
  )
  
  puts "Deleted quote: #{quote_id}"
  
  # Return 204 No Content
  {
    statusCode: 204,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Headers' => 'Content-Type',
      'Access-Control-Allow-Methods' => 'DELETE,OPTIONS'
    },
    body: ''
  }
  
rescue S3Client::S3Error => e
  puts "S3 error: #{e.message}"
  ResponseHelper.error(500, 'S3Error', "Failed to delete photos: #{e.message}")
rescue DbClient::DbError => e
  puts "Database error: #{e.message}"
  ResponseHelper.error(500, 'DatabaseError', 'Failed to delete quote')
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
  puts e.backtrace
  ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
end

