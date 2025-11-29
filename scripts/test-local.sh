#!/bin/bash

# Local testing script for ArborQuote API
# Tests all endpoints against LocalStack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
LOCALSTACK_ENDPOINT="http://localhost:4566"
STAGE="local"

echo "======================================"
echo "  ArborQuote Local API Tests"
echo "======================================"
echo ""

# Check if LocalStack is running
echo "🔍 Checking LocalStack..."
if ! curl -s "${LOCALSTACK_ENDPOINT}/_localstack/health" > /dev/null; then
    echo -e "${RED}❌ LocalStack is not running!${NC}"
    echo "Start it with: docker-compose up -d"
    exit 1
fi
echo -e "${GREEN}✓ LocalStack is running${NC}"
echo ""

# Get API Gateway ID
echo "🔍 Finding API Gateway..."
API_ID=$(aws --endpoint-url="${LOCALSTACK_ENDPOINT}" apigatewayv2 get-apis \
    --query "Items[?Name=='ArborQuoteApi'].ApiId" \
    --output text 2>/dev/null || echo "")

if [ -z "$API_ID" ]; then
    echo -e "${RED}❌ API Gateway not found!${NC}"
    echo "Deploy the stack with: cdklocal deploy"
    exit 1
fi

API_URL="${LOCALSTACK_ENDPOINT}/restapis/${API_ID}/${STAGE}/_user_request_"
echo -e "${GREEN}✓ API Gateway found: ${API_ID}${NC}"
echo "   API URL: ${API_URL}"
echo ""

# Test 1: Create a Quote
echo "📝 Test 1: Create a Quote"
CREATE_RESPONSE=$(curl -s -X POST \
    "${API_URL}/quotes" \
    -H "Content-Type: application/json" \
    -d '{
        "userId": "user_001",
        "customerName": "John Doe",
        "customerPhone": "555-1234",
        "customerAddress": "123 Oak Street",
        "items": [
            {
                "type": "tree_removal",
                "description": "Large oak tree",
                "diameterInInches": 36,
                "heightInFeet": 45,
                "riskFactors": ["near_structure"],
                "price": 85000
            },
            {
                "type": "stump_grinding",
                "description": "Grind stump",
                "price": 25000
            }
        ],
        "notes": "Customer wants work before winter"
    }')

echo "$CREATE_RESPONSE" | jq .

if echo "$CREATE_RESPONSE" | jq -e '.quoteId' > /dev/null; then
    QUOTE_ID=$(echo "$CREATE_RESPONSE" | jq -r '.quoteId')
    echo -e "${GREEN}✓ Quote created: ${QUOTE_ID}${NC}"
else
    echo -e "${RED}❌ Failed to create quote${NC}"
    exit 1
fi
echo ""

# Test 2: Get the Quote
echo "📖 Test 2: Get Quote by ID"
GET_RESPONSE=$(curl -s "${API_URL}/quotes/${QUOTE_ID}")
echo "$GET_RESPONSE" | jq .

if echo "$GET_RESPONSE" | jq -e '.quoteId' > /dev/null; then
    echo -e "${GREEN}✓ Quote retrieved successfully${NC}"
else
    echo -e "${RED}❌ Failed to get quote${NC}"
fi
echo ""

# Test 3: List Quotes for User
echo "📋 Test 3: List Quotes for User"
LIST_RESPONSE=$(curl -s "${API_URL}/quotes?userId=user_001")
echo "$LIST_RESPONSE" | jq .

if echo "$LIST_RESPONSE" | jq -e '.quotes' > /dev/null; then
    QUOTE_COUNT=$(echo "$LIST_RESPONSE" | jq '.count')
    echo -e "${GREEN}✓ Found ${QUOTE_COUNT} quote(s)${NC}"
else
    echo -e "${RED}❌ Failed to list quotes${NC}"
fi
echo ""

# Test 4: Update the Quote
echo "✏️  Test 4: Update Quote Status"
UPDATE_RESPONSE=$(curl -s -X PUT \
    "${API_URL}/quotes/${QUOTE_ID}" \
    -H "Content-Type: application/json" \
    -d '{
        "status": "sent",
        "notes": "Sent to customer via email"
    }')

echo "$UPDATE_RESPONSE" | jq .

if echo "$UPDATE_RESPONSE" | jq -e '.status' > /dev/null; then
    NEW_STATUS=$(echo "$UPDATE_RESPONSE" | jq -r '.status')
    echo -e "${GREEN}✓ Quote updated, status: ${NEW_STATUS}${NC}"
else
    echo -e "${RED}❌ Failed to update quote${NC}"
fi
echo ""

# Test 5: Error Handling - Invalid Item Type
echo "🚫 Test 5: Error Handling - Invalid Item Type"
ERROR_RESPONSE=$(curl -s -X POST \
    "${API_URL}/quotes" \
    -H "Content-Type: application/json" \
    -d '{
        "userId": "user_001",
        "customerName": "Jane Doe",
        "customerPhone": "555-5678",
        "customerAddress": "456 Pine Street",
        "items": [
            {
                "type": "invalid_type",
                "description": "This should fail"
            }
        ]
    }')

echo "$ERROR_RESPONSE" | jq .

if echo "$ERROR_RESPONSE" | jq -e '.error' > /dev/null; then
    ERROR_TYPE=$(echo "$ERROR_RESPONSE" | jq -r '.error')
    echo -e "${GREEN}✓ Error handled correctly: ${ERROR_TYPE}${NC}"
else
    echo -e "${YELLOW}⚠ Expected error response${NC}"
fi
echo ""

# Test 6: Error Handling - Missing Required Fields
echo "🚫 Test 6: Error Handling - Missing Required Fields"
ERROR_RESPONSE=$(curl -s -X POST \
    "${API_URL}/quotes" \
    -H "Content-Type: application/json" \
    -d '{
        "userId": "user_001"
    }')

echo "$ERROR_RESPONSE" | jq .

if echo "$ERROR_RESPONSE" | jq -e '.error' > /dev/null; then
    echo -e "${GREEN}✓ Validation error handled correctly${NC}"
else
    echo -e "${YELLOW}⚠ Expected validation error${NC}"
fi
echo ""

# Test 7: Query DynamoDB Directly
echo "💾 Test 7: Verify Data in DynamoDB"
DYNAMO_SCAN=$(aws --endpoint-url="${LOCALSTACK_ENDPOINT}" dynamodb scan \
    --table-name "ArborQuote-Quotes-${STAGE}" \
    --query "Count" \
    --output text 2>/dev/null || echo "0")

echo "   Items in DynamoDB: ${DYNAMO_SCAN}"
if [ "$DYNAMO_SCAN" -gt 0 ]; then
    echo -e "${GREEN}✓ Data persisted to DynamoDB${NC}"
else
    echo -e "${YELLOW}⚠ No items found in DynamoDB${NC}"
fi
echo ""

echo "======================================"
echo -e "${GREEN}✅ All tests completed!${NC}"
echo "======================================"

