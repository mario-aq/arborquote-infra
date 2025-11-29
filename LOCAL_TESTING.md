# Local Testing with LocalStack

This guide explains how to test the ArborQuote backend infrastructure locally using LocalStack and CDK Local.

## Prerequisites

- Docker Desktop installed and running
- Node.js and npm installed
- AWS CDK installed (`npm install -g aws-cdk`)
- AWS CDK Local installed (`npm install -g aws-cdk-local`)
- AWS CLI installed
- awslocal CLI (optional): `pip install awscli-local`
- Ruby 3.2.0 with bundler

## Quick Start

### 1. Start LocalStack

```bash
# Start LocalStack container
docker-compose up -d

# Check that LocalStack is running
docker ps | grep localstack

# View LocalStack logs
docker-compose logs -f localstack
```

### 2. Configure AWS CLI for LocalStack

```bash
# Set environment variables for LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566

# Or use awslocal (if installed via pip)
# awslocal is a wrapper that automatically sets the endpoint
pip install awscli-local
```

### 3. Deploy Stack to LocalStack

```bash
# Bootstrap CDK (first time only)
cdklocal bootstrap

# Deploy the stack
cdklocal deploy --require-approval never

# Note: You may need to set stage explicitly
cdklocal deploy ArborQuoteBackendStack-local --require-approval never
```

### 4. Get API Gateway URL

```bash
# List API Gateway APIs
awslocal apigatewayv2 get-apis

# Get the API endpoint from the output
# It should be something like: http://localhost:4566/restapis/{api-id}/local/_user_request_
```

## Manual Testing

### Example API Calls

Once deployed, you can test the API endpoints. Replace `{API_ID}` with your actual API Gateway ID.

#### 1. Create a Quote

```bash
curl -X POST \
  "http://localhost:4566/restapis/{API_ID}/local/_user_request_/quotes" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_001",
    "customerName": "John Doe",
    "customerPhone": "555-1234",
    "customerAddress": "123 Oak Street",
    "items": [
      {
        "type": "tree_removal",
        "description": "Large oak tree near house",
        "diameterInInches": 36,
        "heightInFeet": 45,
        "riskFactors": ["near_structure"],
        "price": 85000
      },
      {
        "type": "stump_grinding",
        "description": "Grind stump after removal",
        "price": 25000
      }
    ],
    "notes": "Customer wants work done before winter"
  }'
```

#### 2. List Quotes for a User

```bash
curl "http://localhost:4566/restapis/{API_ID}/local/_user_request_/quotes?userId=user_001"
```

#### 3. Get a Specific Quote

```bash
# Use the quoteId from the create response
curl "http://localhost:4566/restapis/{API_ID}/local/_user_request_/quotes/{QUOTE_ID}"
```

#### 4. Update a Quote

```bash
curl -X PUT \
  "http://localhost:4566/restapis/{API_ID}/local/_user_request_/quotes/{QUOTE_ID}" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "sent",
    "notes": "Updated: sent to customer via email"
  }'
```

## Viewing LocalStack Resources

### DynamoDB Tables

```bash
# List tables
awslocal dynamodb list-tables

# Scan quotes table
awslocal dynamodb scan --table-name ArborQuote-Quotes-local

# Scan users table
awslocal dynamodb scan --table-name ArborQuote-Users-local
```

### Lambda Functions

```bash
# List Lambda functions
awslocal lambda list-functions

# Invoke a function directly
awslocal lambda invoke \
  --function-name ArborQuoteBackendStack-local-CreateQuoteFunction \
  --payload '{"body": "{\"userId\":\"test\"}"}' \
  response.json

cat response.json
```

### CloudWatch Logs

```bash
# List log groups
awslocal logs describe-log-groups

# Get logs for a specific function
awslocal logs tail /aws/lambda/ArborQuoteBackendStack-local-CreateQuoteFunction --follow
```

## Troubleshooting

### LocalStack not starting

```bash
# Stop and remove containers
docker-compose down

# Remove volumes
docker volume prune

# Start fresh
docker-compose up -d
```

### CDK deploy fails

```bash
# Ensure LocalStack is running
docker ps | grep localstack

# Check CDK context
cdklocal context --clear

# Try deploying with verbose output
cdklocal deploy --verbose
```

### Lambda functions not working

```bash
# Check Lambda logs
awslocal logs tail /aws/lambda/{FunctionName} --follow

# Verify Lambda function exists
awslocal lambda get-function --function-name {FunctionName}

# Check IAM roles
awslocal iam list-roles
```

### Can't connect to LocalStack

```bash
# Verify LocalStack is listening
curl http://localhost:4566/_localstack/health

# Check Docker network
docker network inspect arborquote-local

# Restart LocalStack
docker-compose restart
```

## Cleanup

```bash
# Stop LocalStack
docker-compose down

# Remove volumes and data
docker-compose down -v
rm -rf localstack-data

# Unset environment variables
unset AWS_ENDPOINT_URL
```

## Tips

1. **Use LocalStack Pro** for better Lambda compatibility (optional, paid)
2. **Check logs frequently** - LocalStack logs are very helpful for debugging
3. **Ruby Lambda quirks** - LocalStack may have issues with Ruby layers, ensure your Gemfile.lock is committed
4. **API Gateway paths** - LocalStack uses a different path structure than real AWS
5. **Persistence** - By default, data is not persisted between restarts. Set `PERSISTENCE=1` in docker-compose.yml if needed

## Alternative: Using SAM Local

If LocalStack has issues with Ruby Lambdas, you can also use AWS SAM:

```bash
# Install SAM CLI
brew install aws-sam-cli

# Generate SAM template from CDK
cdk synth --no-staging > template.yaml

# Start local API
sam local start-api --template template.yaml
```

## Next Steps

- Add integration tests that run against LocalStack
- Set up CI/CD pipeline with LocalStack
- Create test data fixtures
- Add performance testing scripts

