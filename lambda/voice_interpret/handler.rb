require 'json'
require 'base64'
require_relative '../shared/db_client'
require_relative '../shared/openai_client'

# Lambda handler for voice-first quote interpretation
# POST /quotes/voice-interpret
def lambda_handler(event:, context:)
  puts "Event: #{JSON.generate(event)}"

  # Parse request body
  body = JSON.parse(event['body'] || '{}')
  
  # Validate request
  validate_voice_request(body)
  
  # Decode audio from base64
  audio_binary = Base64.strict_decode64(body['audioBase64'])
  puts "Decoded audio: #{audio_binary.bytesize} bytes"
  
  # Transcribe audio using Whisper
  transcript_result = OpenAiClient.transcribe_audio(
    audio_binary: audio_binary,
    mime_type: body['audioMimeType']
  )
  
  transcript = transcript_result[:text]
  language = transcript_result[:language]
  
  # Sanitize quote draft (remove PII before sending to GPT)
  sanitized_draft = sanitize_quote_for_gpt(body['quoteDraft'])
  
  # Interpret voice instructions using GPT
  updated_draft = OpenAiClient.interpret_voice_instructions(
    transcript: transcript,
    language: language,
    quote_draft: sanitized_draft
  )
  
  # Return response (frontend will merge with PII)
  ResponseHelper.success(200, {
    transcript: transcript,
    detectedLanguage: language,
    updatedQuoteDraft: updated_draft
  })
  
rescue ValidationError => e
  puts "Validation error: #{e.message}"
  ResponseHelper.error(400, 'ValidationError', e.message)
rescue OpenAiClient::TranscriptionError => e
  puts "Transcription error: #{e.message}"
  ResponseHelper.error(502, 'TranscriptionError', e.message)
rescue OpenAiClient::InterpretationError => e
  puts "Interpretation error: #{e.message}"
  ResponseHelper.error(502, 'InterpretationError', e.message)
rescue JSON::ParserError => e
  puts "JSON parse error: #{e.message}"
  ResponseHelper.error(400, 'InvalidJSON', 'Request body must be valid JSON')
rescue ArgumentError => e
  # Base64 decode error
  puts "Base64 decode error: #{e.message}"
  ResponseHelper.error(400, 'ValidationError', 'Invalid base64 audio data')
rescue StandardError => e
  puts "Unexpected error: #{e.class.name} - #{e.message}"
  puts e.backtrace
  ResponseHelper.error(500, 'InternalServerError', 'An unexpected error occurred')
end

# Validate voice request structure and constraints
def validate_voice_request(body)
  # Required fields
  unless body['audioBase64'] && body['audioMimeType'] && body['quoteDraft']
    raise ValidationError, 'Missing required fields: audioBase64, audioMimeType, and quoteDraft are required'
  end
  
  # Audio size check (base64 encoded)
  # Base64 inflates by ~33%, so 7.5MB base64 ≈ 5.6MB raw
  # API Gateway HTTP API has 10MB payload limit
  max_base64_size = 7_500_000  # ~7.5MB base64
  if body['audioBase64'].length > max_base64_size
    raise ValidationError, 'Audio size exceeds limit (max ~5MB decoded audio)'
  end
  
  # Valid MIME types
  valid_mime_types = [
    'audio/webm',
    'audio/mp4',
    'audio/m4a',
    'audio/ogg',
    'audio/wav',
    'audio/mpeg'
  ]
  
  unless valid_mime_types.include?(body['audioMimeType'])
    raise ValidationError, "Invalid audio MIME type. Supported types: #{valid_mime_types.join(', ')}"
  end
  
  # Basic base64 validation (pattern check)
  unless body['audioBase64'].is_a?(String) && body['audioBase64'].match?(/^[A-Za-z0-9+\/]+=*$/)
    raise ValidationError, 'Invalid base64 audio data format'
  end
  
  # Quote draft must be a hash
  unless body['quoteDraft'].is_a?(Hash)
    raise ValidationError, 'quoteDraft must be an object'
  end
  
  # Quote draft should have items array (even if empty)
  unless body['quoteDraft']['items'].is_a?(Array)
    raise ValidationError, 'quoteDraft must have an items array'
  end
end

# Sanitize quote for GPT (remove PII fields)
# Frontend will merge changes back into full quote with PII
def sanitize_quote_for_gpt(quote)
  sanitized = quote.dup
  
  # Remove customer PII
  sanitized.delete('customerName')
  sanitized.delete('customerPhone')
  sanitized.delete('customerEmail')
  sanitized.delete('customerAddress')
  
  # Remove user/company identifiers
  sanitized.delete('userId')
  sanitized.delete('companyId')
  
  # Remove timestamps (not needed for interpretation)
  sanitized.delete('createdAt')
  sanitized.delete('updatedAt')
  
  # Remove PDF-related fields (not relevant)
  sanitized.delete('pdfS3Key')
  sanitized.delete('pdfS3KeyEn')
  sanitized.delete('pdfS3KeyEs')
  sanitized.delete('lastPdfHash')
  sanitized.delete('lastPdfHashEn')
  sanitized.delete('lastPdfHashEs')
  
  # Keep: quoteId (for reference), status, items, totalPrice, notes
  # This gives GPT context about the quote structure without exposing PII
  
  sanitized
end

# Custom error class for validation
class ValidationError < StandardError; end

