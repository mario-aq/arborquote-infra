# Voice-First Quoting Feature

Voice-first quoting allows tree service providers to update quotes by speaking instructions in Spanish, English, or mixed (Spanglish). The system transcribes audio using OpenAI Whisper and interprets instructions using GPT-4o-mini.

## Architecture

- **Endpoint**: `POST /quotes/voice-interpret`
- **Flow**: Audio (base64) → Whisper transcription → GPT interpretation → Updated quote draft
- **Stateless**: Does NOT write to DynamoDB; returns updated draft for frontend to merge
- **Privacy**: Customer/provider PII is stripped before sending to AI models
- **Storage**: Audio processed in-memory only (not stored in S3)

## Setup

### 1. Install Dependencies

```bash
cd lambda
bundle install
```

This will install the `ruby-openai` gem (~> 7.0) required for OpenAI API access.

### 2. Set OpenAI API Key

You need an OpenAI API key with access to Whisper and GPT-4o models.

#### For Local Testing:

```bash
export OPENAI_API_KEY="sk-proj-..."
```

#### For CDK Deployment:

```bash
OPENAI_API_KEY="sk-proj-..." npx cdk deploy ArborQuoteBackendStack-dev
```

Or set in your shell profile:

```bash
# ~/.zshrc or ~/.bashrc
export OPENAI_API_KEY="sk-proj-..."
```

### 3. Deploy

```bash
npm install
OPENAI_API_KEY="sk-proj-..." npx cdk deploy ArborQuoteBackendStack-dev
```

## Usage

### Request Format

```json
POST /quotes/voice-interpret
Content-Type: application/json

{
  "audioBase64": "UklGRi4AAABXQVZFZm10IBAAAAABAAEA...",
  "audioMimeType": "audio/webm",
  "quoteDraft": {
    "quoteId": "01ARZ3NDEKTSV4RRFFQ69G5FAV",
    "userId": "user_001",
    "customerName": "John Doe",
    "customerPhone": "555-1234",
    "customerAddress": "123 Oak St",
    "status": "draft",
    "items": [
      {
        "itemId": "01HQXYZITEM1234567890ABCDE",
        "type": "tree_removal",
        "description": "Large oak tree",
        "price": 85000,
        "riskFactors": ["near_structure"],
        "photos": []
      }
    ],
    "totalPrice": 85000,
    "notes": ""
  }
}
```

### Response Format

```json
{
  "transcript": "Para el primer árbol, bájale doscientos dólares y márcalo como cerca de la casa",
  "detectedLanguage": "es",
  "updatedQuoteDraft": {
    "quoteId": "01ARZ3NDEKTSV4RRFFQ69G5FAV",
    "status": "draft",
    "items": [
      {
        "itemId": "01HQXYZITEM1234567890ABCDE",
        "type": "tree_removal",
        "description": "Large oak tree",
        "price": 65000,
        "riskFactors": ["near_structure"],
        "photos": []
      }
    ],
    "totalPrice": 65000,
    "notes": ""
  }
}
```

**Note**: The `updatedQuoteDraft` does NOT include PII fields (customerName, customerPhone, etc.). The frontend should merge these changes with the original quote:

```javascript
const mergedQuote = {
  ...originalQuote,  // Keeps customerName, customerPhone, etc.
  ...updatedQuoteDraft,  // Merges items, prices, notes, status
};
```

## Voice Instruction Examples

### Spanish Examples

| Voice Instruction | Result |
|-------------------|--------|
| "Bájale 200 dólares al primer árbol" | Subtract $200 from first item price |
| "Agregar poda de un árbol por $150" | Add new pruning item for $150 |
| "El segundo árbol está cerca de cables" | Add "near_powerlines" risk factor to item 2 |
| "Cambiar las notas: cliente quiere el trabajo urgente" | Update notes field |
| "Marcar como enviado" | Change status to "sent" |
| "Quitar el tercer item" | Remove third item from quote |

### English Examples

| Voice Instruction | Result |
|-------------------|--------|
| "Reduce the first tree by $200" | Subtract $200 from first item price |
| "Add stump grinding for $150" | Add new stump grinding item for $150 |
| "Mark the second one as leaning" | Add "leaning" risk factor to item 2 |
| "Update notes to say customer wants morning appointments" | Update notes field |
| "Change status to sent" | Change status to "sent" |
| "Remove the third item" | Remove third item from quote |

### Mixed (Spanglish) Examples

| Voice Instruction | Result |
|-------------------|--------|
| "El primer tree está leaning y diseased" | Add risk factors to first item |
| "Add un cleanup service por doscientos dólares" | Add cleanup item for $200 |

## Audio Requirements

- **Max Size**: ~5MB decoded audio (~7.5MB base64)
- **Max Duration**: ~2 minutes recommended
- **Supported Formats**: 
  - `audio/webm` (recommended for web)
  - `audio/mp4` / `audio/m4a`
  - `audio/ogg`
  - `audio/wav`
  - `audio/mpeg`

## Error Handling

| Status | Error Code | Description |
|--------|------------|-------------|
| 400 | ValidationError | Missing fields, invalid base64, audio too large |
| 502 | TranscriptionError | Whisper API failed to transcribe |
| 502 | InterpretationError | GPT failed to interpret or returned invalid JSON |
| 500 | InternalServerError | Unexpected server error |

## Environment Variables

The Lambda function uses these environment variables:

- `OPENAI_API_KEY` (required): OpenAI API key
- `OPENAI_TRANSCRIBE_MODEL` (default: `whisper-1`): Whisper model to use
- `OPENAI_GPT_MODEL` (default: `gpt-4o-mini`): GPT model for interpretation

### Changing Models

To use a different GPT model (e.g., full `gpt-4o`):

```bash
OPENAI_GPT_MODEL="gpt-4o" npx cdk deploy ArborQuoteBackendStack-dev
```

## Cost Considerations

**Whisper API Pricing** (as of Dec 2024):
- $0.006 per minute of audio
- 2-minute audio ≈ $0.012

**GPT-4o-mini Pricing** (as of Dec 2024):
- Input: $0.150 per 1M tokens
- Output: $0.600 per 1M tokens
- Typical call: ~500 input + ~300 output tokens ≈ $0.00026

**Per voice interpretation**: ~$0.013 (mostly Whisper cost)

For 1000 voice interactions/month: ~$13

## Privacy & Security

- **PII Protection**: Customer names, phone numbers, emails, and addresses are stripped before sending to OpenAI
- **Audio Storage**: Audio is processed in-memory only and never stored in S3
- **Transcripts**: Not logged in production (only in debug mode)
- **API Key**: Should be stored in AWS Secrets Manager for production (currently env var)

## Testing Locally

See `LOCAL_TESTING.md` for instructions on testing the voice endpoint with local DynamoDB and S3.

Quick test with curl:

```bash
# Record audio and convert to base64
base64 -i recording.webm > audio.b64

# Send to API
curl -X POST https://api-dev.arborquote.app/quotes/voice-interpret \
  -H "Content-Type: application/json" \
  -d '{
    "audioBase64": "'$(cat audio.b64)'",
    "audioMimeType": "audio/webm",
    "quoteDraft": {
      "status": "draft",
      "items": [],
      "totalPrice": 0,
      "notes": ""
    }
  }'
```

## Future Enhancements

Possible improvements (not yet implemented):

1. **S3 Audit Trail**: Optionally store audio in temp bucket for debugging/compliance
2. **Streaming Responses**: Stream transcript and updates as they're generated
3. **Multi-turn Conversations**: Allow back-and-forth clarifications
4. **Custom Vocabulary**: Train on tree service terminology
5. **Confidence Scores**: Return confidence levels for interpreted changes
6. **Undo/Redo**: Track change history for voice edits

## Troubleshooting

### "Missing OPENAI_API_KEY" Error

Make sure you set the environment variable before deploying:

```bash
export OPENAI_API_KEY="sk-proj-..."
npx cdk deploy ArborQuoteBackendStack-dev
```

### "Audio size exceeds limit" Error

- Check audio file size before encoding to base64
- Compress audio or reduce recording duration
- Use a more efficient format like webm or m4a

### "Failed to transcribe audio" Error

- Verify audio format is supported
- Check if audio is corrupted or too quiet
- Ensure OpenAI API key has Whisper access

### "Failed to interpret voice instructions" Error

- Check if GPT model is available (e.g., gpt-4o-mini)
- Verify OpenAI API key has GPT access
- Check CloudWatch logs for detailed error messages

## Support

For issues or questions:
- Check CloudWatch logs: `/aws/lambda/ArborQuote-VoiceInterpret-{stage}`
- Review OpenAPI spec: `openapi.yaml`
- See test examples: `scripts/test-voice.sh` (coming soon)

