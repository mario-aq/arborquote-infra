require 'openai'
require 'json'
require 'tempfile'

# OpenAI API client for voice transcription (Whisper) and instruction interpretation (GPT)
module OpenAiClient
  class << self
    # Initialize OpenAI client (lazy-loaded)
    def client
      @client ||= OpenAI::Client.new(
        access_token: ENV['OPENAI_API_KEY'],
        request_timeout: 30 # 30 second timeout for API calls
      )
    end

    # Transcribe audio using Whisper
    # @param audio_binary [String] Raw audio bytes
    # @param mime_type [String] Audio MIME type (e.g., 'audio/webm')
    # @return [Hash] { text: String, language: String }
    def transcribe_audio(audio_binary:, mime_type:)
      # Create temp file for Whisper API (requires file-like object)
      extension = extension_from_mime_type(mime_type)
      temp_file = Tempfile.new(['audio', ".#{extension}"])
      
      begin
        temp_file.binmode
        temp_file.write(audio_binary)
        temp_file.rewind
        
        puts "Calling Whisper API with #{audio_binary.bytesize} bytes (#{mime_type})"
        
        response = client.audio.transcribe(
          parameters: {
            model: ENV['OPENAI_TRANSCRIBE_MODEL'] || 'whisper-1',
            file: temp_file,
          }
        )
        
        text = response.dig('text') || ''
        language = response.dig('language') || 'unknown'
        
        puts "Whisper transcription successful: #{text.length} chars, language: #{language}"
        
        {
          text: text,
          language: language
        }
      rescue => e
        puts "Whisper API error: #{e.message}"
        raise TranscriptionError.new("Failed to transcribe audio: #{e.message}")
      ensure
        temp_file.close
        temp_file.unlink
      end
    end

    # Interpret voice instructions using GPT
    # @param transcript [String] Transcribed text
    # @param language [String] Detected language code
    # @param quote_draft [Hash] Current quote object (sanitized, no PII)
    # @return [Hash] Updated quote object
    def interpret_voice_instructions(transcript:, language:, quote_draft:)
      system_prompt = build_system_prompt
      user_prompt = build_user_prompt(transcript, language, quote_draft)
      
      puts "Calling GPT API to interpret instructions (#{transcript.length} chars)"
      
      begin
        response = client.chat(
          parameters: {
            model: ENV['OPENAI_GPT_MODEL'] || 'gpt-4o-mini',
            messages: [
              { role: 'system', content: system_prompt },
              { role: 'user', content: user_prompt }
            ],
            temperature: 0.1, # Low temperature for consistent, predictable output
            response_format: { type: 'json_object' } # Force JSON response
          }
        )
        
        content = response.dig('choices', 0, 'message', 'content')
        
        if content.nil? || content.strip.empty?
          raise InterpretationError.new('GPT returned empty response')
        end
        
        # Parse JSON response
        updated_quote = JSON.parse(content)
        
        puts "GPT interpretation successful: #{updated_quote['items']&.length || 0} items"
        
        updated_quote
      rescue JSON::ParserError => e
        puts "Failed to parse GPT response as JSON: #{e.message}"
        raise InterpretationError.new('Failed to parse GPT response as valid JSON')
      rescue => e
        puts "GPT API error: #{e.message}"
        raise InterpretationError.new("Failed to interpret voice instructions: #{e.message}")
      end
    end

    private

    # Map MIME type to file extension
    def extension_from_mime_type(mime_type)
      case mime_type
      when 'audio/webm' then 'webm'
      when 'audio/mp4', 'audio/m4a' then 'm4a'
      when 'audio/ogg' then 'ogg'
      when 'audio/wav' then 'wav'
      when 'audio/mpeg' then 'mp3'
      else 'audio'
      end
    end

    # Build GPT system prompt (instructions for interpreting voice commands)
    def build_system_prompt
      <<~PROMPT
        You are a voice instruction interpreter for ArborQuote, a tree service quoting system.

        Your job: Update a quote draft based on voice instructions from a tree service provider.

        ## Quote Structure
        - `status`: "draft" | "sent" | "accepted" | "rejected"
        - `items`: Array of service items:
          - `itemId`: Unique ID (preserve existing IDs, generate new for added items)
          - `type`: "tree_removal" | "pruning" | "stump_grinding" | "cleanup" | "trimming" | "emergency_service" | "other"
          - `description`: Work description
          - `diameterInInches`, `heightInFeet`: Optional tree dimensions (numbers)
          - `riskFactors`: Optional array: "near_structure", "near_powerlines", "leaning", "diseased", "dead", "difficult_access", "other"
          - `price`: Price in cents (integer, e.g., 85000 = $850.00)
          - `photos`: Array of S3 keys (NEVER modify these)
        - `totalPrice`: Sum of all item prices in cents
        - `notes`: General notes (string)

        ## Rules
        1. Users speak Spanish, English, or mixed (Spanglish)
        2. Common instructions:
           - Add/modify items
           - Change prices: "$200" or "doscientos dólares" = 20000 cents
           - "Bájale 50 dólares" = subtract 5000 cents
           - Update notes
           - Add/remove risk factors
           - Change status
        3. Item references:
           - "primer árbol" / "first tree" / "item 1" = items[0]
           - "segundo" / "second" / "item 2" = items[1]
           - By description: "el roble" matches item with "roble" or "oak" in description
        4. Preserve all existing itemIds and photos arrays unchanged
        5. Recalculate totalPrice after any price changes
        6. For new items, generate itemId as "NEW_ITEM_1", "NEW_ITEM_2", etc.
        7. Return valid JSON only (no markdown, no explanations, no code blocks)
        8. If instruction is unclear, make best guess or leave quote unchanged

        ## Examples
        - "Bájale 200 al primer árbol" → Subtract 20000 from items[0].price, recalc total
        - "Add stump grinding for $150" → New item: type="stump_grinding", price=15000, itemId="NEW_ITEM_1"
        - "Mark the second one as leaning and near powerlines" → Add to items[1].riskFactors
        - "Change notes to say customer wants this done next week" → Update notes field
        - "Remove the third item" → Remove items[2], recalc total
      PROMPT
    end

    # Build GPT user prompt with transcript and current quote
    def build_user_prompt(transcript, language, quote_draft)
      <<~PROMPT
        Voice transcript (detected language: #{language}):
        "#{transcript}"

        Current quote draft:
        #{JSON.pretty_generate(quote_draft)}

        Interpret the voice instruction and return the updated quote as a JSON object. Only include the quote structure itself, no additional text.
      PROMPT
    end
  end

  # Custom error classes
  class TranscriptionError < StandardError; end
  class InterpretationError < StandardError; end
end

