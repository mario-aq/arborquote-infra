# ArborQuote Infrastructure

AWS CDK infrastructure for the ArborQuote MVP backend - a tree-service quoting tool.

## Architecture Overview

This project defines a serverless backend API built on AWS using:

- **API Gateway (HTTP API)** - REST endpoints for quote management
- **Lambda Functions (Ruby 3.2)** - Serverless compute for business logic
- **DynamoDB** - NoSQL database for users and quotes
- **S3** - Object storage for quote item photos
- **CloudWatch Logs** - Centralized logging

### Design Principles

- ✅ **Cost-optimized** - Designed to stay within AWS Free Tier
- ✅ **Serverless** - No servers to manage, pay only for what you use
- ✅ **Infrastructure as Code** - Everything defined in AWS CDK (TypeScript)
- ✅ **Least privilege IAM** - Each Lambda has minimal required permissions
- ✅ **Simple & maintainable** - Clear separation of concerns

## Resource Overview

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/quotes` | Create a new quote |
| GET | `/quotes?userId={userId}` | List all quotes for a user |
| GET | `/quotes/{quoteId}` | Get a specific quote by ID |
| PUT | `/quotes/{quoteId}` | Update an existing quote |

### Lambda Functions

| Function | Runtime | Memory | Purpose |
|----------|---------|--------|---------|
| CreateQuote | Ruby 3.2 | 128 MB | Create new quotes |
| ListQuotes | Ruby 3.2 | 128 MB | Query quotes by userId |
| GetQuote | Ruby 3.2 | 128 MB | Retrieve single quote |
| UpdateQuote | Ruby 3.2 | 128 MB | Update quote fields |

### DynamoDB Tables

#### UsersTable
- **Partition Key**: `userId` (String)
- **Attributes**: name, email, phone, createdAt, updatedAt
- **Billing**: On-demand (free tier: 25 WCU, 25 RCU)

#### QuotesTable
- **Partition Key**: `quoteId` (String, ULID format)
- **GSI**: `userId-index` (partition: userId, sort: createdAt)
- **Attributes**: userId, customerName, customerPhone, customerAddress, jobType, notes, photos, status, price, createdAt, updatedAt
- **Billing**: On-demand

#### PhotosBucket (S3)
- **Purpose**: Store quote item photos
- **Path Structure**: `{YYYY}/{MM}/{DD}/{userId}/{quoteId}/{itemIndex}/{filename}`
- **Encryption**: Server-side (AES256)
- **Access**: Private bucket, photos accessed via presigned URLs (1-hour expiration)
- **Lifecycle**: Transition to Glacier Deep Archive after 90 days
- **Limits**: 
  - Max 10 items per quote
  - Max 3 photos per item
  - Max 5MB per photo
  - Supported formats: JPEG, PNG, WebP

## Data Models

### Quote Object

```json
{
  "quoteId": "01HQXYZ9ABC...",          // ULID (time-sortable, 26 chars)
  "userId": "user_12345",               // Owner of the quote
  "customerName": "John Doe",
  "customerPhone": "555-1234",
  "customerAddress": "123 Oak Street, Springfield, IL",
  "status": "draft",                    // "draft" | "sent" | "accepted" | "rejected"
  "items": [                            // Array of line items (trees/tasks)
    {
      "itemId": "01HQXYZITEM1...",      // ULID for this item
      "type": "tree_removal",           // See Item Types below
      "description": "Large oak tree in backyard, leaning toward house",
      "diameterInInches": 36,           // Trunk diameter (optional)
      "heightInFeet": 45,               // Tree height (optional)
      "riskFactors": [                  // Array of risk factors (optional)
        "near_structure",
        "leaning"
      ],
      "price": 85000,                   // Price for this item (cents)
      "photos": [                       // S3 keys or presigned URLs
        "2025/11/29/user_12345/01HQXYZ9ABC/0/tree-front.jpg"
      ]
    },
    {
      "itemId": "01HQXYZITEM2...",
      "type": "stump_grinding",
      "description": "Grind remaining stump from oak removal",
      "diameterInInches": 36,
      "heightInFeet": null,
      "riskFactors": [],
      "price": 25000,
      "photos": []
    }
  ],
  "totalPrice": 110000,                 // Sum of all item prices (cents)
  "notes": "Customer wants work completed before winter.",
  "createdAt": "2025-11-29T12:00:00Z",
  "updatedAt": "2025-11-29T12:00:00Z"
}
```

### Item Types

Valid values for `item.type`:
- `tree_removal` - Complete tree removal
- `pruning` - Tree pruning/trimming
- `stump_grinding` - Stump removal
- `cleanup` - Debris removal and cleanup
- `trimming` - Light trimming work
- `emergency_service` - Emergency tree services
- `other` - Other services

### User Object

```json
{
  "userId": "user_12345",
  "name": "Jane Smith",
  "email": "jane@example.com",
  "phone": "555-5678",
  "createdAt": "2025-11-29T10:00:00Z",
  "updatedAt": "2025-11-29T10:00:00Z"
}
```

## Prerequisites

Before deploying, ensure you have:

1. **Node.js** (v18 or later)
   ```bash
   node --version  # Should be v18+
   ```

2. **AWS CLI** configured with credentials
   ```bash
   aws --version
   aws configure list  # Verify credentials are set
   ```

3. **AWS Account** with appropriate permissions to create:
   - DynamoDB tables
   - Lambda functions
   - API Gateway
   - IAM roles
   - CloudWatch log groups

4. **AWS CDK** (installed automatically via npm)

## AWS Credentials Setup

### Option 1: Named Profile (Recommended)

1. Configure a named AWS profile:
   ```bash
   aws configure --profile arborquote
   ```
   
   You'll be prompted for:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (e.g., `us-east-1`)
   - Default output format (e.g., `json`)

2. Deploy using the profile:
   ```bash
   cdk deploy --profile arborquote
   ```

### Option 2: Default Profile

If you want to use your default AWS credentials:

```bash
aws configure
# Enter your credentials when prompted
```

Then deploy without the `--profile` flag:
```bash
cdk deploy
```

### Option 3: Environment Variables

Set temporary credentials:
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

## Installation & Deployment

### Local Development First (Recommended)

Before deploying to AWS, test locally with LocalStack:

```bash
# Install CDK Local (first time only)
npm install -g aws-cdk-local

# Install awslocal CLI (Python - optional but recommended)
pip install awscli-local

# Start LocalStack
npm run local:start

# Deploy to LocalStack
npm run local:deploy

# Run manual API tests
npm run local:test

# Stop LocalStack when done
npm run local:stop
```

📖 **See [LOCAL_TESTING.md](LOCAL_TESTING.md) for complete local testing guide**

### Deploy to AWS

### 1. Install Dependencies

```bash
npm install
```

This will install:
- AWS CDK libraries
- TypeScript compiler
- All required dependencies

### 2. Build the CDK App

```bash
npm run build
```

This compiles TypeScript to JavaScript.

### 3. Bootstrap CDK (First Time Only)

If this is your first time using CDK in your AWS account/region:

```bash
cdk bootstrap aws://ACCOUNT-ID/REGION --profile arborquote
```

To get your account ID:
```bash
aws sts get-caller-identity --profile arborquote --query Account --output text
```

Example:
```bash
cdk bootstrap aws://123456789012/us-east-1 --profile arborquote
```

**Note**: You only need to bootstrap once per account/region combination.

### 4. Review Changes (Optional)

Preview what will be created:

```bash
cdk synth --profile arborquote
```

This generates the CloudFormation template.

### 5. Deploy the Stack

Deploy to AWS:

```bash
cdk deploy --profile arborquote
```

You'll be asked to approve IAM changes. Type `y` and press Enter.

Deployment typically takes 2-3 minutes.

### 6. Save the Output

After deployment completes, you'll see output like:

```
Outputs:
ArborQuoteBackendStack-dev.ApiEndpoint = https://abc123xyz.execute-api.us-east-1.amazonaws.com
ArborQuoteBackendStack-dev.QuotesTableName = ArborQuote-Quotes-dev
ArborQuoteBackendStack-dev.UsersTableName = ArborQuote-Users-dev
ArborQuoteBackendStack-dev.Region = us-east-1
```

**Save the `ApiEndpoint` URL** - you'll need it to make API requests.

## Testing the API

### Create a Quote

```bash
curl -X POST https://YOUR_API_ENDPOINT/quotes \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_test_001",
    "customerName": "John Doe",
    "customerPhone": "555-1234",
    "customerAddress": "123 Oak Street, Springfield",
    "jobType": "tree removal",
    "notes": "Large oak tree in backyard, approx 40ft tall",
    "price": 50000
  }'
```

Expected response (201 Created):
```json
{
  "quoteId": "01HQXYZ...",
  "userId": "user_test_001",
  "customerName": "John Doe",
  "status": "draft",
  "createdAt": "2025-11-29T12:00:00Z",
  ...
}
```

### List Quotes for a User

```bash
curl "https://YOUR_API_ENDPOINT/quotes?userId=user_test_001"
```

Expected response (200 OK):
```json
{
  "quotes": [
    {
      "quoteId": "01HQXYZ...",
      "customerName": "John Doe",
      ...
    }
  ],
  "count": 1,
  "userId": "user_test_001"
}
```

### Get a Specific Quote

```bash
curl "https://YOUR_API_ENDPOINT/quotes/01HQXYZ..."
```

### Update a Quote

```bash
curl -X PUT https://YOUR_API_ENDPOINT/quotes/01HQXYZ... \
  -H "Content-Type: application/json" \
  -d '{
    "price": 60000,
    "status": "sent",
    "notes": "Updated pricing after site visit"
  }'
```

## Photo Management

ArborQuote supports uploading photos for each quote item (tree, service, etc.) to provide visual context.

### Photo Storage Architecture

- **Storage**: S3 bucket with server-side encryption (AES256)
- **Path Structure**: `{YYYY}/{MM}/{DD}/{userId}/{quoteId}/{itemIndex}/{filename}`
- **Access Control**: Private bucket - photos accessed via presigned URLs
- **URL Expiration**: Presigned URLs expire after 1 hour
- **Lifecycle**: Photos transition to Glacier Deep Archive after 90 days
- **Validation**:
  - Max 10 items per quote
  - Max 3 photos per item  
  - Max 5MB per photo
  - Allowed formats: JPEG, PNG, WebP

### How Photos Work

1. **On Create/Update**: Client uploads photos as base64-encoded data
2. **Storage**: Lambda decodes and uploads to S3 with date-based paths
3. **Database**: DynamoDB stores S3 keys (not URLs)
4. **On Retrieval**: Lambda generates presigned URLs valid for 1 hour

### Upload Photos with a Quote

Photos are included in the `items` array as base64-encoded data:

```bash
curl -X POST $API_ENDPOINT/quotes \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_001",
    "customerName": "Jane Smith",
    "customerPhone": "555-7890",
    "customerAddress": "456 Pine Street",
    "items": [
      {
        "type": "tree_removal",
        "description": "Dead oak near house",
        "price": 85000,
        "photos": [
          {
            "data": "/9j/4AAQSkZJRgABAQEAYABgAAD...",
            "contentType": "image/jpeg",
            "filename": "tree-front.jpg"
          },
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAA...",
            "contentType": "image/png",
            "filename": "tree-damage.png"
          }
        ]
      }
    ]
  }'
```

**Convert image to base64:**
```bash
# macOS/Linux
base64 -i photo.jpg

# Or store in variable
PHOTO_BASE64=$(base64 -i photo.jpg)
```

### Retrieve Photos

When fetching quotes, photo S3 keys are automatically converted to presigned URLs:

```bash
curl "$API_ENDPOINT/quotes/01HQXYZ..."
```

Response includes presigned URLs:
```json
{
  "quoteId": "01HQXYZ...",
  "items": [
    {
      "itemId": "01HQXYZITEM1...",
      "photos": [
        "https://arborquote-photos-dev.s3.amazonaws.com/2025/11/29/user_001/01HQXYZ/0/tree-front.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=...",
        "https://arborquote-photos-dev.s3.amazonaws.com/2025/11/29/user_001/01HQXYZ/0/tree-damage.png?X-Amz-Algorithm=..."
      ]
    }
  ]
}
```

**Important**: URLs expire after 1 hour. Fetch fresh URLs by calling GET again.

### Update Photos

Mix existing photos (S3 keys) with new uploads (base64 data):

```bash
curl -X PUT $API_ENDPOINT/quotes/01HQXYZ... \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {
        "itemId": "01HQXYZITEM1...",
        "photos": [
          "2025/11/29/user_001/01HQXYZ/0/tree-front.jpg",
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAA...",
            "contentType": "image/jpeg",
            "filename": "new-angle.jpg"
          }
        ]
      }
    ]
  }'
```

### Remove Photos

Set `photos` to empty array to remove all photos:

```bash
curl -X PUT $API_ENDPOINT/quotes/01HQXYZ... \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {
        "itemId": "01HQXYZITEM1...",
        "photos": []
      }
    ]
  }'
```

**Note**: Photos remain in S3 for 90 days before archiving to Glacier.

### Photo Validation Errors

**Too many photos per item:**
```json
{
  "error": "ValidationError",
  "message": "Item 0: Maximum 3 photos allowed per item"
}
```

**Photo too large:**
```json
{
  "error": "ValidationError",
  "message": "Item 0, Photo 0: Photo size exceeds maximum of 5MB"
}
```

**Invalid format:**
```json
{
  "error": "ValidationError",
  "message": "Item 0, Photo 0: Invalid content type 'image/gif'. Allowed types: image/jpeg, image/png, image/webp"
}
```

**Invalid base64:**
```json
{
  "error": "S3Error",
  "message": "Failed to upload photos: Invalid base64 data"
}
```

📖 **See [API_EXAMPLES.md](API_EXAMPLES.md) for more photo examples**

## Project Structure

```
arborquote-infra/
├── README.md                          # This file
├── package.json                       # Node.js dependencies
├── tsconfig.json                      # TypeScript configuration
├── cdk.json                          # CDK app configuration
├── .gitignore                        # Git ignore rules
├── bin/
│   └── arborquote-infra.ts           # CDK app entry point
├── lib/
│   └── arborquote-backend-stack.ts   # Main infrastructure stack
└── lambda/
    ├── shared/
    │   ├── db_client.rb              # Shared utilities (DynamoDB, validation, responses)
    │   └── s3_client.rb              # S3 photo upload/download utilities
    ├── create_quote/
    │   └── handler.rb                # POST /quotes
    ├── list_quotes/
    │   └── handler.rb                # GET /quotes
    ├── get_quote/
    │   └── handler.rb                # GET /quotes/{quoteId}
    └── update_quote/
        └── handler.rb                # PUT /quotes/{quoteId}
```

## Cost Estimates (AWS Free Tier)

### Monthly Free Tier Limits

| Service | Free Tier | Notes |
|---------|-----------|-------|
| **DynamoDB** | 25 GB storage, 25 WCU, 25 RCU | On-demand billing included |
| **Lambda** | 1M requests/month, 400K GB-seconds | ARM64 architecture |
| **API Gateway (HTTP)** | 1M requests/month (first 12 months) | After: $1/million requests |
| **CloudWatch Logs** | 5 GB ingestion, 5 GB storage | 7-day retention |

### Expected MVP Costs

For light testing (< 1,000 requests/month):
- **Months 1-12**: $0/month (within free tier)
- **After 12 months**: $0-2/month

**Tip**: Use on-demand billing for DynamoDB to avoid provisioned capacity charges.

## Useful Commands

| Command | Description |
|---------|-------------|
| `npm install` | Install dependencies |
| `npm run build` | Compile TypeScript |
| `npm run watch` | Watch for changes and recompile |
| `cdk synth` | Generate CloudFormation template |
| `cdk diff` | Compare deployed stack with current state |
| `cdk deploy` | Deploy stack to AWS |
| `cdk destroy` | Delete all resources (cleanup) |

### Deploying to Different Stages

Deploy to production:

```bash
cdk deploy --profile arborquote --context stage=prod
```

Deploy to different region:

```bash
cdk deploy --profile arborquote --context region=us-west-2
```

## Viewing Logs

View Lambda logs in CloudWatch:

```bash
# List log groups
aws logs describe-log-groups --profile arborquote | grep ArborQuote

# Tail logs for a specific function
aws logs tail /aws/lambda/ArborQuote-CreateQuote-dev --follow --profile arborquote
```

Or use the AWS Console:
1. Go to CloudWatch → Log groups
2. Find `/aws/lambda/ArborQuote-*-dev`
3. View log streams

## Testing

ArborQuote includes comprehensive tests for all Lambda functions.

### Run Tests

```bash
cd lambda
bundle install
bundle exec rspec
```

Or use the test script:

```bash
cd lambda
chmod +x run_tests.sh
./run_tests.sh
```

### Test Coverage

Tests cover:
- ✅ All Lambda handlers (create, update, get, list)
- ✅ Shared utilities and validation
- ✅ Error handling and edge cases
- ✅ DynamoDB integration (mocked)

Target: **80% minimum coverage**

View coverage report:
```bash
cd lambda
bundle exec rspec
open coverage/index.html
```

### Test Structure

```
lambda/
├── spec/
│   ├── spec_helper.rb              # RSpec configuration
│   ├── shared/
│   │   └── db_client_spec.rb       # Shared utilities tests
│   ├── create_quote_spec.rb        # Create quote tests
│   ├── update_quote_spec.rb        # Update quote tests
│   ├── get_quote_spec.rb           # Get quote tests
│   └── list_quotes_spec.rb         # List quotes tests
└── TESTING.md                      # Detailed testing guide
```

For detailed testing instructions, see [`lambda/TESTING.md`](lambda/TESTING.md).

## Cleanup

To delete all resources and avoid any charges:

```bash
cdk destroy --profile arborquote
```

Type `y` to confirm deletion.

**Warning**: This will permanently delete:
- All DynamoDB tables and data
- All Lambda functions
- API Gateway endpoints
- CloudWatch logs

## Troubleshooting

### "No credentials found"

Make sure AWS credentials are configured:
```bash
aws configure --profile arborquote
aws sts get-caller-identity --profile arborquote
```

### "Stack already exists"

If deployment fails midway, try:
```bash
cdk deploy --profile arborquote --force
```

### "Insufficient permissions"

Ensure your AWS user/role has permissions for:
- DynamoDB (CreateTable, PutItem, GetItem, etc.)
- Lambda (CreateFunction, UpdateFunctionCode, etc.)
- API Gateway (CreateApi, CreateRoute, etc.)
- IAM (CreateRole, AttachRolePolicy)
- CloudFormation (CreateStack, UpdateStack)

### Lambda errors in CloudWatch

Check CloudWatch logs for detailed error messages:
```bash
aws logs tail /aws/lambda/ArborQuote-CreateQuote-dev --profile arborquote
```

### DynamoDB quota exceeded

Free tier includes 25 GB storage and 25 WCU/RCU. For MVP, this should be sufficient. Monitor usage in AWS Console → DynamoDB → Tables.

## Next Steps (Future Enhancements)

Currently **out of scope** for MVP:

- [ ] **Authentication** - Add Cognito user pools, JWT validation
- [ ] **Authorization** - Implement role-based access control
- [ ] **PDF Generation** - Generate quote PDFs using Lambda + S3
- [ ] **Photo Upload** - S3 pre-signed URLs for image uploads
- [ ] **AI Estimation** - Integrate AI for automatic pricing (`POST /quotes/estimate`)
- [ ] **Email Notifications** - SES for sending quotes to customers
- [ ] **Rate Limiting** - API keys or throttling
- [ ] **CI/CD Pipeline** - GitHub Actions or AWS CodePipeline
- [ ] **Monitoring & Alarms** - CloudWatch alarms for errors/latency
- [ ] **Multi-region** - Deploy to multiple regions for HA

## Support

For issues or questions:
1. Check CloudWatch logs for error details
2. Review the API response error messages
3. Verify AWS credentials and permissions
4. Ensure you're within free tier limits

## License

Proprietary - ArborQuote Internal Use Only
