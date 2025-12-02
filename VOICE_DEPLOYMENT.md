# Voice Feature Deployment Guide

Quick guide to deploy the voice-first quoting feature to your ArborQuote backend.

## Prerequisites

1. **OpenAI API Key** with access to:
   - Whisper (transcription)
   - GPT-4o or GPT-4o-mini (interpretation)

2. **Existing ArborQuote Infrastructure** deployed (dev or prod)

3. **AWS CLI** configured with credentials

## Step-by-Step Deployment

### 1. Install Ruby Dependencies

The voice feature requires the `ruby-openai` gem:

```bash
cd lambda
bundle install
```

This will install:
- `ruby-openai ~> 7.0` (OpenAI API client)
- All existing dependencies

### 2. Set OpenAI API Key

#### Option A: Environment Variable (Recommended for Dev)

```bash
export OPENAI_API_KEY="sk-proj-..."
```

Add to your shell profile for persistence:
```bash
# ~/.zshrc or ~/.bashrc
export OPENAI_API_KEY="sk-proj-..."
```

#### Option B: AWS Secrets Manager (Recommended for Prod)

```bash
# Create secret
aws secretsmanager create-secret \
  --name arborquote/openai-api-key \
  --secret-string "sk-proj-..." \
  --region us-east-1

# Update CDK to read from Secrets Manager (future enhancement)
```

### 3. Build CDK App

```bash
cd /path/to/arborquote-infra
npm install
npm run build
```

### 4. Deploy to AWS

```bash
# Dev environment
OPENAI_API_KEY="sk-proj-..." npx cdk deploy ArborQuoteBackendStack-dev

# Prod environment (when ready)
OPENAI_API_KEY="sk-proj-..." npx cdk deploy ArborQuoteBackendStack-prod --context stage=prod
```

**Note**: The `OPENAI_API_KEY` env var must be set during deployment for the Lambda to receive it.

### 5. Verify Deployment

Check CloudFormation outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name ArborQuoteBackendStack-dev \
  --query 'Stacks[0].Outputs' \
  --output table
```

You should see:
- `VoiceInterpretFunction` Lambda created
- API endpoint includes `/quotes/voice-interpret`

### 6. Test the Endpoint

#### Quick Test (No Audio)

```bash
export API_ENDPOINT="https://api-dev.arborquote.app"

curl -X POST $API_ENDPOINT/quotes/voice-interpret \
  -H "Content-Type: application/json" \
  -d '{
    "audioBase64": "test",
    "audioMimeType": "audio/webm",
    "quoteDraft": {"items": [], "status": "draft"}
  }'
```

Should return validation error (expected - proves endpoint is working).

#### Full Test with Audio

Use the test script:

```bash
# Record a short voice note (e.g., "Add a tree removal for $500")
# Convert to webm or m4a format

./scripts/test-voice.sh recording.webm dev
```

Expected response:
```json
{
  "transcript": "Add a tree removal for $500",
  "detectedLanguage": "en",
  "updatedQuoteDraft": {
    "items": [
      {
        "itemId": "NEW_ITEM_1",
        "type": "tree_removal",
        "description": "...",
        "price": 50000
      }
    ],
    "totalPrice": 50000
  }
}
```

## Environment Variables Reference

The voice Lambda uses these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | *(required)* | OpenAI API key |
| `OPENAI_TRANSCRIBE_MODEL` | `whisper-1` | Whisper model for transcription |
| `OPENAI_GPT_MODEL` | `gpt-4o-mini` | GPT model for interpretation |

### Changing Models

To use a different GPT model:

```bash
OPENAI_API_KEY="sk-proj-..." \
OPENAI_GPT_MODEL="gpt-4o" \
npx cdk deploy ArborQuoteBackendStack-dev
```

## Cost Estimates

### Per Voice Interaction

- **Whisper**: $0.006/minute → ~$0.012 for 2-min audio
- **GPT-4o-mini**: ~$0.0003 per call (input + output tokens)
- **Total**: ~$0.013 per voice interaction

### Monthly Costs (Estimated)

| Usage | Monthly Cost |
|-------|--------------|
| 100 voice interactions | $1.30 |
| 500 voice interactions | $6.50 |
| 1000 voice interactions | $13.00 |

**Lambda costs**: Included in AWS Free Tier (1M requests/month)

## Troubleshooting

### "Missing OPENAI_API_KEY" Error

**Symptom**: Lambda returns 500 error, CloudWatch logs show "access_token is required"

**Solution**: Ensure env var is set during deployment:
```bash
OPENAI_API_KEY="sk-proj-..." npx cdk deploy ArborQuoteBackendStack-dev
```

### "Audio size exceeds limit" Error

**Symptom**: 400 error, message says audio too large

**Solution**: 
- Compress audio before upload
- Use efficient format like webm or m4a
- Reduce recording duration to < 2 minutes

### "Failed to transcribe audio" Error

**Symptom**: 502 error, TranscriptionError in response

**Solution**:
- Verify OpenAI API key has Whisper access
- Check audio format is supported (webm, m4a, ogg, wav, mp3)
- Ensure audio file is not corrupted
- Check CloudWatch logs for detailed Whisper error

### "Failed to interpret voice instructions" Error

**Symptom**: 502 error, InterpretationError in response

**Solution**:
- Verify OpenAI API key has GPT access
- Check if model name is correct (`gpt-4o-mini` vs `gpt-4o`)
- Review CloudWatch logs for GPT API error details
- Ensure quota/billing is active on OpenAI account

### View Lambda Logs

```bash
# Tail logs in real-time
aws logs tail /aws/lambda/ArborQuote-VoiceInterpret-dev --follow

# View last 5 minutes
aws logs tail /aws/lambda/ArborQuote-VoiceInterpret-dev --since 5m
```

## Security Best Practices

### Production Deployment

For production, use AWS Secrets Manager instead of environment variables:

1. **Create secret**:
```bash
aws secretsmanager create-secret \
  --name arborquote/openai-api-key \
  --secret-string "sk-proj-..." \
  --region us-east-1
```

2. **Update CDK** (future enhancement):
```typescript
const openAiSecret = secretsmanager.Secret.fromSecretNameV2(
  this, 'OpenAiSecret', 
  'arborquote/openai-api-key'
);

environment: {
  OPENAI_API_KEY_SECRET_ARN: openAiSecret.secretArn,
}
```

3. **Update Lambda to read from Secrets Manager** (future enhancement)

### API Key Rotation

Rotate OpenAI API keys regularly:

1. Generate new key in OpenAI dashboard
2. Update AWS secret or redeploy with new env var
3. Revoke old key

## Rollback

If you need to rollback the voice feature:

### Option 1: Keep Lambda, Remove from API

Comment out route in CDK:

```typescript
// httpApi.addRoutes({
//   path: '/quotes/voice-interpret',
//   methods: [apigatewayv2.HttpMethod.POST],
//   integration: voiceInterpretIntegration,
// });
```

Redeploy:
```bash
npx cdk deploy ArborQuoteBackendStack-dev
```

### Option 2: Full Rollback

Revert CDK changes and redeploy:

```bash
git revert <commit-hash>
npx cdk deploy ArborQuoteBackendStack-dev
```

## Monitoring

### CloudWatch Metrics to Watch

- **VoiceInterpret Lambda**:
  - Invocations
  - Errors
  - Duration (should be < 20s)
  - Throttles

- **API Gateway**:
  - 4XX errors (client issues)
  - 5XX errors (server issues)
  - Latency (p50, p99)

### Set Up Alarms (Recommended)

```bash
# Create alarm for Lambda errors
aws cloudwatch put-metric-alarm \
  --alarm-name ArborQuote-VoiceInterpret-Errors \
  --alarm-description "Alert on voice interpret errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=ArborQuote-VoiceInterpret-dev
```

## Next Steps

Once deployed and tested:

1. **Update Frontend**: Integrate voice recording UI
2. **Add Analytics**: Track voice interaction success rates
3. **Optimize Prompts**: Tune GPT prompt based on real usage
4. **Add Feedback Loop**: Let users rate AI interpretations
5. **Expand Languages**: Test with more languages (Portuguese, etc.)

## Support

For issues:
- Check [VOICE_FEATURE.md](VOICE_FEATURE.md) for detailed documentation
- View CloudWatch logs: `/aws/lambda/ArborQuote-VoiceInterpret-{stage}`
- Review OpenAPI spec: `openapi.yaml` (VoiceInterpretRequest/Response schemas)
- Test with: `./scripts/test-voice.sh`

