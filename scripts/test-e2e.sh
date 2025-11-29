#!/bin/bash

# ArborQuote API End-to-End Tests
# Tests all CRUD operations and photo management features

# Don't exit on error - we want to run all tests and report results
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_ENDPOINT="${API_ENDPOINT:-https://api-dev.arborquote.app}"
AWS_PROFILE="${AWS_PROFILE:-arborquote}"
AWS_REGION="${AWS_REGION:-us-east-1}"
S3_BUCKET="arborquote-photos-dev"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
print_header() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}\n"
}

print_test() {
  echo -e "${YELLOW}TEST: $1${NC}"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
  ((TESTS_PASSED++))
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
  ((TESTS_FAILED++))
}

# Cleanup function
cleanup() {
  echo -e "\n${BLUE}Cleaning up test data...${NC}"
  
  # Delete test quotes if they exist
  for QUOTE_ID in "${TEST_QUOTE_IDS[@]}"; do
    if [ ! -z "$QUOTE_ID" ]; then
      curl -s -X DELETE "$API_ENDPOINT/quotes/$QUOTE_ID" -o /dev/null 2>&1 || true
    fi
  done
  
  echo "Cleanup complete"
}

# Array to store test quote IDs for cleanup
declare -a TEST_QUOTE_IDS

# Trap to ensure cleanup runs on exit
trap cleanup EXIT

# Start tests
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ArborQuote API E2E Test Suite        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo "API Endpoint: $API_ENDPOINT"
echo "AWS Profile: $AWS_PROFILE"
echo "AWS Region: $AWS_REGION"

# ========================================
# Test 1: Create Simple Quote (No Photos)
# ========================================
print_header "Test 1: Create Simple Quote"

print_test "Creating quote without photos..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "e2e_test_user_001",
    "customerName": "Test Customer 1",
    "customerPhone": "555-0001",
    "customerAddress": "123 Test St",
    "items": [
      {
        "type": "tree_removal",
        "description": "Simple test tree",
        "price": 50000
      }
    ]
  }')

QUOTE_ID_1=$(echo "$RESPONSE" | jq -r '.quoteId')
TEST_QUOTE_IDS+=("$QUOTE_ID_1")

if [ "$QUOTE_ID_1" != "null" ] && [ ! -z "$QUOTE_ID_1" ]; then
  print_success "Quote created: $QUOTE_ID_1"
else
  print_error "Failed to create quote"
  echo "Response: $RESPONSE"
fi

# ========================================
# Test 2: Create Quote with Base64 Photos
# ========================================
print_header "Test 2: Create Quote with Base64 Photos"

print_test "Creating quote with inline base64 photo..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "e2e_test_user_002",
    "customerName": "Test Customer 2",
    "customerPhone": "555-0002",
    "customerAddress": "456 Test Ave",
    "items": [
      {
        "type": "tree_removal",
        "description": "Tree with photo",
        "price": 75000,
        "photos": [
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            "contentType": "image/png",
            "filename": "test-pixel.png"
          }
        ]
      }
    ]
  }')

QUOTE_ID_2=$(echo "$RESPONSE" | jq -r '.quoteId')
ITEM_ID_2=$(echo "$RESPONSE" | jq -r '.items[0].itemId')
PHOTO_KEY_2=$(echo "$RESPONSE" | jq -r '.items[0].photos[0]')
TEST_QUOTE_IDS+=("$QUOTE_ID_2")

if [ "$QUOTE_ID_2" != "null" ] && [ ! -z "$QUOTE_ID_2" ]; then
  print_success "Quote created: $QUOTE_ID_2"
  
  # Verify S3 path uses itemId
  if echo "$PHOTO_KEY_2" | grep -q "$ITEM_ID_2"; then
    print_success "Photo path uses itemId: $PHOTO_KEY_2"
  else
    print_error "Photo path doesn't use itemId: $PHOTO_KEY_2"
  fi
  
  # Verify photo exists in S3
  if aws s3 ls "s3://$S3_BUCKET/$PHOTO_KEY_2" --profile "$AWS_PROFILE" --region "$AWS_REGION" > /dev/null 2>&1; then
    print_success "Photo uploaded to S3"
  else
    print_error "Photo not found in S3"
  fi
else
  print_error "Failed to create quote with photo"
  echo "Response: $RESPONSE"
fi

# ========================================
# Test 3: Get Quote (with Presigned URLs)
# ========================================
print_header "Test 3: Get Quote with Presigned URLs"

print_test "Fetching quote $QUOTE_ID_2..."
RESPONSE=$(curl -s "$API_ENDPOINT/quotes/$QUOTE_ID_2")

PHOTO_URL=$(echo "$RESPONSE" | jq -r '.items[0].photos[0]')

if echo "$PHOTO_URL" | grep -q "https://"; then
  print_success "Presigned URL generated: ${PHOTO_URL:0:80}..."
else
  print_error "No presigned URL in response"
  echo "Response: $RESPONSE"
fi

# ========================================
# Test 4: List Quotes
# ========================================
print_header "Test 4: List Quotes for User"

print_test "Listing quotes for e2e_test_user_002..."
RESPONSE=$(curl -s "$API_ENDPOINT/quotes?userId=e2e_test_user_002")

QUOTE_COUNT=$(echo "$RESPONSE" | jq '.quotes | length')

if [ "$QUOTE_COUNT" -ge 1 ]; then
  print_success "Found $QUOTE_COUNT quote(s)"
else
  print_error "Expected at least 1 quote, got $QUOTE_COUNT"
fi

# ========================================
# Test 5: Independent Photo Upload
# ========================================
print_header "Test 5: Upload Photos Independently"

print_test "Uploading photos via POST /photos..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT/photos" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "e2e_test_user_003",
    "itemId": "01HQXYZITEM123456789",
    "photos": [
      {
        "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
        "contentType": "image/png",
        "filename": "independent-1.png"
      },
      {
        "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==",
        "contentType": "image/png",
        "filename": "independent-2.png"
      }
    ]
  }')

S3_KEY_1=$(echo "$RESPONSE" | jq -r '.photos[0].s3Key')
S3_KEY_2=$(echo "$RESPONSE" | jq -r '.photos[1].s3Key')

if [ "$S3_KEY_1" != "null" ] && [ ! -z "$S3_KEY_1" ]; then
  print_success "Photo 1 uploaded: $S3_KEY_1"
else
  print_error "Failed to upload photo 1"
fi

if [ "$S3_KEY_2" != "null" ] && [ ! -z "$S3_KEY_2" ]; then
  print_success "Photo 2 uploaded: $S3_KEY_2"
else
  print_error "Failed to upload photo 2"
fi

# ========================================
# Test 6: Create Quote with Pre-uploaded Photos (S3 Keys)
# ========================================
print_header "Test 6: Create Quote with S3 Keys"

print_test "Creating quote using pre-uploaded photo S3 keys..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d "{
    \"userId\": \"e2e_test_user_003\",
    \"customerName\": \"Test Customer 3\",
    \"customerPhone\": \"555-0003\",
    \"customerAddress\": \"789 Test Blvd\",
    \"items\": [
      {
        \"type\": \"tree_removal\",
        \"description\": \"Tree with pre-uploaded photos\",
        \"price\": 60000,
        \"photos\": [\"$S3_KEY_1\", \"$S3_KEY_2\"]
      }
    ]
  }")

QUOTE_ID_3=$(echo "$RESPONSE" | jq -r '.quoteId')
TEST_QUOTE_IDS+=("$QUOTE_ID_3")

if [ "$QUOTE_ID_3" != "null" ] && [ ! -z "$QUOTE_ID_3" ]; then
  print_success "Quote created with pre-uploaded photos: $QUOTE_ID_3"
  
  # Verify photos in response
  PHOTO_COUNT=$(echo "$RESPONSE" | jq '.items[0].photos | length')
  if [ "$PHOTO_COUNT" -eq 2 ]; then
    print_success "Quote contains 2 photos"
  else
    print_error "Expected 2 photos, got $PHOTO_COUNT"
  fi
else
  print_error "Failed to create quote with S3 keys"
  echo "Response: $RESPONSE"
fi

# ========================================
# Test 7: Update Quote
# ========================================
print_header "Test 7: Update Quote"

print_test "Updating quote status to 'sent'..."
RESPONSE=$(curl -s -X PUT "$API_ENDPOINT/quotes/$QUOTE_ID_1" \
  -H 'Content-Type: application/json' \
  -d '{
    "status": "sent"
  }')

UPDATED_STATUS=$(echo "$RESPONSE" | jq -r '.status')

if [ "$UPDATED_STATUS" = "sent" ]; then
  print_success "Quote status updated to 'sent'"
else
  print_error "Failed to update status. Got: $UPDATED_STATUS"
fi

# ========================================
# Test 8: Update Quote - Add Photo to Existing Item
# ========================================
print_header "Test 8: Add Photo to Existing Quote"

# First get the quote to get itemId
QUOTE_DATA=$(curl -s "$API_ENDPOINT/quotes/$QUOTE_ID_1")
ITEM_ID_1=$(echo "$QUOTE_DATA" | jq -r '.items[0].itemId')

print_test "Adding photo to existing item..."
RESPONSE=$(curl -s -X PUT "$API_ENDPOINT/quotes/$QUOTE_ID_1" \
  -H 'Content-Type: application/json' \
  -d "{
    \"items\": [
      {
        \"itemId\": \"$ITEM_ID_1\",
        \"type\": \"tree_removal\",
        \"description\": \"Simple test tree with added photo\",
        \"price\": 50000,
        \"photos\": [
          {
            \"data\": \"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==\",
            \"contentType\": \"image/png\",
            \"filename\": \"added-photo.png\"
          }
        ]
      }
    ]
  }")

PHOTO_COUNT=$(echo "$RESPONSE" | jq '.items[0].photos | length')

if [ "$PHOTO_COUNT" -ge 1 ]; then
  print_success "Photo added to existing quote"
else
  print_error "Failed to add photo"
fi

# ========================================
# Test 9: Delete Individual Photo
# ========================================
print_header "Test 9: Delete Individual Photo"

print_test "Deleting photo via DELETE /photos..."
HTTP_CODE=$(curl -s -w "%{http_code}" -X DELETE "$API_ENDPOINT/photos" \
  -H 'Content-Type: application/json' \
  -d "{\"s3Key\": \"$S3_KEY_1\", \"userId\": \"e2e_test_user_003\"}" \
  -o /dev/null)

if [ "$HTTP_CODE" = "204" ]; then
  print_success "Photo deleted (HTTP 204)"
else
  print_error "Photo deletion failed (HTTP $HTTP_CODE)"
fi

# Verify photo is gone from S3
sleep 1
if ! aws s3 ls "s3://$S3_BUCKET/$S3_KEY_1" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>&1 | grep -q "png"; then
  print_success "Photo removed from S3"
else
  print_error "Photo still in S3"
fi

# ========================================
# Test 10: Delete Quote (with Photo Cleanup)
# ========================================
print_header "Test 10: Delete Quote with Photo Cleanup"

# Create a new quote specifically for deletion test
print_test "Creating quote for deletion test..."
CREATE_RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "e2e_test_user_delete",
    "customerName": "Delete Test",
    "customerPhone": "555-9999",
    "customerAddress": "999 Delete St",
    "items": [
      {
        "type": "tree_removal",
        "description": "Tree to be deleted",
        "price": 30000,
        "photos": [
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            "contentType": "image/png",
            "filename": "will-be-deleted.png"
          }
        ]
      }
    ]
  }')

DELETE_QUOTE_ID=$(echo "$CREATE_RESPONSE" | jq -r '.quoteId')
DELETE_PHOTO_KEY=$(echo "$CREATE_RESPONSE" | jq -r '.items[0].photos[0]')

if [ "$DELETE_QUOTE_ID" != "null" ]; then
  print_success "Test quote created: $DELETE_QUOTE_ID"
  
  # Verify photo exists
  if aws s3 ls "s3://$S3_BUCKET/$DELETE_PHOTO_KEY" --profile "$AWS_PROFILE" --region "$AWS_REGION" > /dev/null 2>&1; then
    print_success "Photo exists in S3 before deletion"
  fi
  
  # Delete the quote
  print_test "Deleting quote (should also delete photos)..."
  HTTP_CODE=$(curl -s -w "%{http_code}" -X DELETE "$API_ENDPOINT/quotes/$DELETE_QUOTE_ID" -o /dev/null)
  
  if [ "$HTTP_CODE" = "204" ]; then
    print_success "Quote deleted (HTTP 204)"
  else
    print_error "Quote deletion failed (HTTP $HTTP_CODE)"
  fi
  
  # Verify quote is gone from DynamoDB
  sleep 1
  GET_RESPONSE=$(curl -s "$API_ENDPOINT/quotes/$DELETE_QUOTE_ID")
  if echo "$GET_RESPONSE" | jq -e '.error == "QuoteNotFound"' > /dev/null 2>&1; then
    print_success "Quote removed from DynamoDB"
  else
    print_error "Quote still in DynamoDB"
  fi
  
  # Verify photo is deleted from S3
  sleep 1
  if ! aws s3 ls "s3://$S3_BUCKET/$DELETE_PHOTO_KEY" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>&1 | grep -q "png"; then
    print_success "Photo deleted from S3"
  else
    print_error "Photo still in S3"
  fi
else
  print_error "Failed to create test quote for deletion"
fi

# ========================================
# Test 11: Validation - Invalid Content Type
# ========================================
print_header "Test 11: Validation - Invalid Content Type"

print_test "Testing invalid content type (should fail)..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "e2e_test_validation",
    "customerName": "Validation Test",
    "customerPhone": "555-0000",
    "customerAddress": "Test",
    "items": [
      {
        "type": "tree_removal",
        "description": "Test",
        "price": 10000,
        "photos": [
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            "contentType": "image/gif",
            "filename": "test.gif"
          }
        ]
      }
    ]
  }')

if echo "$RESPONSE" | jq -e '.error == "ValidationError"' > /dev/null 2>&1; then
  print_success "Invalid content type rejected"
else
  print_error "Invalid content type validation failed"
  echo "Response: $RESPONSE"
fi

# ========================================
# Test 12: Validation - Too Many Photos
# ========================================
print_header "Test 12: Validation - Too Many Photos per Item"

print_test "Testing max photos per item (should fail)..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "e2e_test_validation",
    "customerName": "Validation Test",
    "customerPhone": "555-0000",
    "customerAddress": "Test",
    "items": [
      {
        "type": "tree_removal",
        "description": "Test",
        "price": 10000,
        "photos": [
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            "contentType": "image/png",
            "filename": "1.png"
          },
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            "contentType": "image/png",
            "filename": "2.png"
          },
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            "contentType": "image/png",
            "filename": "3.png"
          },
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            "contentType": "image/png",
            "filename": "4.png"
          }
        ]
      }
    ]
  }')

if echo "$RESPONSE" | jq -e '.error == "ValidationError"' > /dev/null 2>&1 && echo "$RESPONSE" | grep -q "Maximum 3 photos"; then
  print_success "Max photos per item enforced"
else
  print_error "Max photos validation failed"
  echo "Response: $RESPONSE"
fi

# ========================================
# Test 13: Validation - Missing Required Fields
# ========================================
print_header "Test 13: Validation - Missing Required Fields"

print_test "Testing required field validation (should fail)..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "test",
    "items": []
  }')

if echo "$RESPONSE" | jq -e '.error == "ValidationError"' > /dev/null 2>&1; then
  print_success "Required field validation working"
else
  print_error "Required field validation failed"
fi

# ========================================
# Test 14: Update Quote - Remove Item (Photo Cleanup)
# ========================================
print_header "Test 14: Remove Item from Quote (Should Delete Photos)"

print_test "Creating a new quote for item removal test..."
CREATE_RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "e2e_test_item_removal",
    "customerName": "Item Removal Test",
    "customerPhone": "555-7777",
    "customerAddress": "777 Removal St",
    "items": [
      {
        "type": "tree_removal",
        "description": "Tree to be removed from quote",
        "price": 40000,
        "photos": [
          {
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            "contentType": "image/png",
            "filename": "item-removal.png"
          }
        ]
      }
    ]
  }')

REMOVAL_QUOTE_ID=$(echo "$CREATE_RESPONSE" | jq -r '.quoteId')
REMOVAL_ITEM_ID=$(echo "$CREATE_RESPONSE" | jq -r '.items[0].itemId')
REMOVAL_PHOTO_KEY=$(echo "$CREATE_RESPONSE" | jq -r '.items[0].photos[0]')

if [ "$REMOVAL_QUOTE_ID" != "null" ]; then
  print_success "Quote created: $REMOVAL_QUOTE_ID"
  TEST_QUOTE_IDS+=("$REMOVAL_QUOTE_ID")
  
  # Verify photo exists
  if aws s3 ls "s3://$S3_BUCKET/$REMOVAL_PHOTO_KEY" --profile "$AWS_PROFILE" --region "$AWS_REGION" > /dev/null 2>&1; then
    print_success "Photo exists before removal"
  fi
  
  print_test "Removing all items from quote (should delete photos)..."
  UPDATE_RESPONSE=$(curl -s -X PUT "$API_ENDPOINT/quotes/$REMOVAL_QUOTE_ID" \
    -H 'Content-Type: application/json' \
    -d '{
      "items": []
    }')
  
  REMAINING_ITEMS=$(echo "$UPDATE_RESPONSE" | jq '.items | length')
  if [ "$REMAINING_ITEMS" -eq 0 ]; then
    print_success "Items removed from quote"
    
    # Verify photos deleted from S3 (give S3 time to propagate)
    sleep 3
    if ! aws s3 ls "s3://$S3_BUCKET/$REMOVAL_PHOTO_KEY" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>&1 | grep -q "png"; then
      print_success "Photos cleaned up from S3 when items removed"
    else
      print_error "Photos still in S3 after item removal"
      echo "Photo key: $REMOVAL_PHOTO_KEY"
    fi
  else
    print_error "Failed to remove items (remaining: $REMAINING_ITEMS)"
  fi
else
  print_error "Failed to create quote for removal test"
fi

# ========================================
# Test Results Summary
# ========================================
print_header "Test Results Summary"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  All Tests Passed! 🎉                 ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
  exit 0
else
  echo -e "${RED}╔════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  Some Tests Failed                     ║${NC}"
  echo -e "${RED}╚════════════════════════════════════════╝${NC}"
  exit 1
fi

