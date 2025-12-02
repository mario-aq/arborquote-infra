#!/bin/bash

# Script to seed test user and company data for PDF testing
# Usage: ./scripts/seed-test-user.sh

set -e

AWS_PROFILE="${AWS_PROFILE:-arborquote}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STAGE="${STAGE:-dev}"

COMPANIES_TABLE="ArborQuote-Companies-${STAGE}"
USERS_TABLE="ArborQuote-Users-${STAGE}"

echo "========================================="
echo "Seeding Test User and Company Data"
echo "========================================="
echo "AWS Profile: $AWS_PROFILE"
echo "AWS Region: $AWS_REGION"
echo "Stage: $STAGE"
echo ""

# Company ID (using a fixed ULID-like ID for consistency)
COMPANY_ID="01HTEST00COMPANY001"
USER_ID="test-user-001"

echo "Creating test company..."
aws dynamodb put-item \
  --table-name "$COMPANIES_TABLE" \
  --item '{
    "companyId": {"S": "'$COMPANY_ID'"},
    "companyName": {"S": "Green Tree Arborist Services LLC"},
    "phone": {"S": "555-TREE-PRO"},
    "email": {"S": "contact@greentreearborist.com"},
    "address": {"S": "789 Arbor Lane, Portland, OR 97201"},
    "website": {"S": "www.greentreearborist.com"},
    "createdAt": {"S": "'"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"'"},
    "updatedAt": {"S": "'"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"'"}
  }' \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"

if [ $? -eq 0 ]; then
  echo "✅ Test company created: $COMPANY_ID"
else
  echo "❌ Failed to create test company"
  exit 1
fi

echo ""
echo "Creating test user..."
aws dynamodb put-item \
  --table-name "$USERS_TABLE" \
  --item '{
    "userId": {"S": "'$USER_ID'"},
    "companyId": {"S": "'$COMPANY_ID'"},
    "name": {"S": "John Rodriguez"},
    "email": {"S": "john@greentreearborist.com"},
    "phone": {"S": "555-TREE-001"},
    "address": {"S": "789 Arbor Lane, Portland, OR 97201"},
    "createdAt": {"S": "'"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"'"},
    "updatedAt": {"S": "'"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"'"}
  }' \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"

if [ $? -eq 0 ]; then
  echo "✅ Test user created: $USER_ID"
else
  echo "❌ Failed to create test user"
  exit 1
fi

echo ""
echo "========================================="
echo "✅ Test Data Seeded Successfully!"
echo "========================================="
echo ""
echo "Test Company:"
echo "  - ID: $COMPANY_ID"
echo "  - Name: Green Tree Arborist Services LLC"
echo "  - Phone: 555-TREE-PRO"
echo "  - Email: contact@greentreearborist.com"
echo "  - Website: www.greentreearborist.com"
echo ""
echo "Test User:"
echo "  - ID: $USER_ID"
echo "  - Name: John Rodriguez"
echo "  - Email: john@greentreearborist.com"
echo "  - Phone: 555-TREE-001"
echo ""
echo "You can now generate PDFs using userId: test-user-001"
echo "The PDF will display company info in the left column."

