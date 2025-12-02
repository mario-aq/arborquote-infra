# Voice Feature - Quick Start

**TL;DR**: Voice-first quoting with OpenAI Whisper + GPT-4o-mini. Speak Spanish/English/mixed to update quotes.

## Deploy in 3 Steps

```bash
# 1. Install dependencies
cd lambda && bundle install && cd ..
npm install && npm run build

# 2. Set OpenAI key & deploy
export OPENAI_API_KEY="sk-proj-..."
npx cdk deploy ArborQuoteBackendStack-dev

# 3. Test
./scripts/test-voice.sh recording.webm dev
```

## API Usage

```bash
curl -X POST https://api-dev.arborquote.app/quotes/voice-interpret \
  -H "Content-Type: application/json" \
  -d '{
    "audioBase64": "'$(base64 -i recording.webm | tr -d '\n')'",
    "audioMimeType": "audio/webm",
    "quoteDraft": {
      "status": "draft",
      "items": [
        {
          "itemId": "01ITEM123",
          "type": "tree_removal",
          "description": "Large oak",
          "price": 85000
        }
      ],
      "totalPrice": 85000,
      "notes": ""
    }
  }'
```

## Response

```json
{
  "transcript": "Bájale doscientos dólares al primer árbol",
  "detectedLanguage": "es",
  "updatedQuoteDraft": {
    "status": "draft",
    "items": [
      {
        "itemId": "01ITEM123",
        "type": "tree_removal",
        "description": "Large oak",
        "price": 65000
      }
    ],
    "totalPrice": 65000,
    "notes": ""
  }
}
```

## Voice Examples

| Say This | Result |
|----------|--------|
| "Bájale $200 al primer árbol" | Subtract $200 from item 1 |
| "Add stump grinding for $150" | New item for $150 |
| "Mark second tree as leaning" | Add "leaning" risk factor |
| "Change notes to say urgent" | Update notes field |
| "Remove third item" | Delete item 3 |

## Frontend Integration

```javascript
// 1. Record audio
const mediaRecorder = new MediaRecorder(stream);
const audioBlob = await recordAudio();

// 2. Convert to base64
const audioBase64 = await blobToBase64(audioBlob);

// 3. Send to API
const response = await fetch('/quotes/voice-interpret', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    audioBase64,
    audioMimeType: 'audio/webm',
    quoteDraft: currentQuote
  })
});

const { transcript, updatedQuoteDraft } = await response.json();

// 4. Merge with current quote (keeps PII)
const mergedQuote = {
  ...currentQuote,
  ...updatedQuoteDraft
};

// 5. Show to user, let them save or discard
```

## Limits

- Max audio: 5MB decoded (~7MB base64)
- Formats: webm, m4a, ogg, wav, mp3
- Duration: < 2 minutes recommended
- Cost: ~$0.013 per voice call

## Troubleshooting

| Error | Fix |
|-------|-----|
| Missing OPENAI_API_KEY | Set env var before deploy |
| Audio size exceeds limit | Compress audio or reduce duration |
| Failed to transcribe | Check audio format and OpenAI quota |
| Failed to interpret | Verify GPT access and model name |

View logs:
```bash
aws logs tail /aws/lambda/ArborQuote-VoiceInterpret-dev --follow
```

## Docs

- **Full docs**: `VOICE_FEATURE.md`
- **Deployment**: `VOICE_DEPLOYMENT.md`
- **Implementation**: `IMPLEMENTATION_SUMMARY.md`
- **API spec**: `openapi.yaml` → `/quotes/voice-interpret`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | *(required)* | OpenAI API key |
| `OPENAI_GPT_MODEL` | `gpt-4o-mini` | GPT model |
| `OPENAI_TRANSCRIBE_MODEL` | `whisper-1` | Whisper model |

Change model:
```bash
OPENAI_GPT_MODEL="gpt-4o" npx cdk deploy ArborQuoteBackendStack-dev
```

## Cost

- **Whisper**: $0.006/min
- **GPT-4o-mini**: $0.0003/call
- **Total**: ~$0.013 per voice interaction
- **1000 calls**: ~$13/month

---

**Questions?** See full docs or check CloudWatch logs.

