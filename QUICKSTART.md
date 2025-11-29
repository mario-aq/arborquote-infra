# Quick Start Guide

Get ArborQuote backend up and running in 5 minutes.

## Prerequisites Checklist

- [ ] Node.js v18+ installed (`node --version`)
- [ ] AWS CLI installed (`aws --version`)
- [ ] AWS credentials configured
- [ ] Git (if cloning from repository)

## 5-Step Deployment

### Step 1: AWS Credentials

Configure your AWS credentials:

```bash
aws configure --profile arborquote
```

Enter:
- **AWS Access Key ID**: Your access key
- **AWS Secret Access Key**: Your secret key
- **Default region**: `us-east-1` (or your preferred region)
- **Default output format**: `json`

Verify it works:
```bash
aws sts get-caller-identity --profile arborquote
```

### Step 2: Install Dependencies

```bash
npm install
```

This installs AWS CDK and all required packages (~2 minutes).

### Step 3: Bootstrap CDK (First Time Only)

Get your AWS account ID:
```bash
aws sts get-caller-identity --profile arborquote --query Account --output text
```

Bootstrap CDK (replace `123456789012` with your account ID):
```bash
cdk bootstrap aws://123456789012/us-east-1 --profile arborquote
```

**Note**: Only needed once per account/region.

### Step 4: Deploy

```bash
npm run build
cdk deploy --profile arborquote
```

Type `y` when asked to approve IAM changes.

Deployment takes ~2-3 minutes.

### Step 5: Test the API

Save your API endpoint from the deployment output:

```bash
export API_ENDPOINT="YOUR_API_ENDPOINT_HERE"
```

Create a test quote:

```bash
curl -X POST $API_ENDPOINT/quotes \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_001",
    "customerName": "John Doe",
    "customerPhone": "555-1234",
    "customerAddress": "123 Oak St",
    "jobType": "tree removal",
    "price": 50000
  }'
```

You should see a JSON response with your new quote!

## What Gets Deployed

After deployment, you'll have:

✅ **API Gateway** - HTTP API with 4 endpoints
✅ **4 Lambda Functions** - Ruby 3.2, ARM64 architecture
✅ **2 DynamoDB Tables** - Users and Quotes with GSI
✅ **IAM Roles** - Least-privilege permissions
✅ **CloudWatch Logs** - Automatic logging for all functions

## Next Steps

1. **Test all endpoints** - See `API_EXAMPLES.md` for curl examples
2. **View logs** - Check CloudWatch for Lambda execution logs
3. **Build your frontend** - Use the API endpoint to integrate with your app
4. **Monitor costs** - Check AWS Cost Explorer (should be $0 in free tier)

## Common Commands

```bash
# Deploy changes
npm run build && cdk deploy --profile arborquote

# View what will change
cdk diff --profile arborquote

# View CloudFormation template
cdk synth --profile arborquote

# Tail Lambda logs
aws logs tail /aws/lambda/ArborQuote-CreateQuote-dev --follow --profile arborquote

# Delete everything
cdk destroy --profile arborquote
```

## Troubleshooting

### "No credentials found"
Run `aws configure --profile arborquote` and enter your credentials.

### "Stack does not exist"
You need to deploy first: `cdk deploy --profile arborquote`

### "Insufficient permissions"
Your AWS user needs permissions for DynamoDB, Lambda, API Gateway, IAM, and CloudFormation.

### Lambda errors
Check CloudWatch logs:
```bash
aws logs tail /aws/lambda/ArborQuote-CreateQuote-dev --profile arborquote
```

### API returns 502 Bad Gateway
Lambda is likely timing out or crashing. Check CloudWatch logs for the specific function.

## Architecture Diagram

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────┐
│      API Gateway (HTTP API)             │
│  POST   /quotes                         │
│  GET    /quotes?userId=xxx              │
│  GET    /quotes/{quoteId}               │
│  PUT    /quotes/{quoteId}               │
└──────┬──────────────────────────────────┘
       │
       ├──────────────────────┬──────────────────┬──────────────────┐
       │                      │                  │                  │
       ▼                      ▼                  ▼                  ▼
┌─────────────┐      ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│   Create    │      │    List     │   │     Get     │   │   Update    │
│   Lambda    │      │   Lambda    │   │   Lambda    │   │   Lambda    │
└──────┬──────┘      └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
       │                     │                  │                  │
       └─────────────────────┴──────────────────┴──────────────────┘
                                    │
                                    ▼
                          ┌────────────────────┐
                          │   DynamoDB Tables  │
                          │  - QuotesTable     │
                          │  - UsersTable      │
                          └────────────────────┘
```

## File Structure

```
arborquote-infra/
├── README.md                   # Full documentation
├── QUICKSTART.md              # This file
├── API_EXAMPLES.md            # API usage examples
├── package.json               # Node.js dependencies
├── cdk.json                   # CDK configuration
├── bin/
│   └── arborquote-infra.ts    # CDK entry point
├── lib/
│   └── arborquote-backend-stack.ts  # Infrastructure definitions
└── lambda/
    ├── shared/
    │   └── db_client.rb       # Shared Ruby utilities
    ├── create_quote/
    │   └── handler.rb
    ├── list_quotes/
    │   └── handler.rb
    ├── get_quote/
    │   └── handler.rb
    └── update_quote/
        └── handler.rb
```

## Cost Estimate

**Free Tier (First 12 months):**
- ✅ DynamoDB: 25 GB storage, 25 RCU/WCU
- ✅ Lambda: 1M requests/month
- ✅ API Gateway: 1M requests/month
- ✅ CloudWatch: 5 GB logs

**Expected cost for MVP testing**: **$0/month**

After free tier expires: **$0-2/month** for light usage.

## Support

- **Full Documentation**: See `README.md`
- **API Examples**: See `API_EXAMPLES.md`
- **CloudWatch Logs**: Check for error details
- **AWS Console**: Review resources in CloudFormation

## Ready to Deploy?

```bash
# 1. Configure AWS
aws configure --profile arborquote

# 2. Install dependencies
npm install

# 3. Bootstrap (first time only)
cdk bootstrap aws://YOUR_ACCOUNT_ID/us-east-1 --profile arborquote

# 4. Deploy
npm run build
cdk deploy --profile arborquote

# 5. Test
curl -X POST YOUR_API_ENDPOINT/quotes -H "Content-Type: application/json" -d '{"userId":"test","customerName":"Test","customerPhone":"555-0000","customerAddress":"123 Test St","jobType":"test"}'
```

Done! 🎉

