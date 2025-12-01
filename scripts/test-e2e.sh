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
PDF_BUCKET="arborquote-quote-pdfs-dev"

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
# Test 15: Generate PDF (English)
# ========================================
print_header "Test 15: Generate PDF (English)"

print_test "Creating quote for PDF generation..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "e2e_pdf_user",
    "customerName": "PDF Test Customer",
    "customerPhone": "555-PDF1",
    "customerAddress": "456 PDF Lane, Springfield, IL 62701",
    "items": [
      {
        "type": "tree_removal",
        "description": "Large oak tree requiring removal",
        "diameterInInches": 48,
        "heightInFeet": 60,
        "riskFactors": ["near_structure", "leaning"],
        "price": 125000
      },
      {
        "type": "stump_grinding",
        "description": "Grind remaining stump",
        "price": 35000
      }
    ],
    "notes": "Customer wants work completed within 2 weeks"
  }')

PDF_QUOTE_ID=$(echo "$RESPONSE" | jq -r '.quoteId')
TEST_QUOTE_IDS+=("$PDF_QUOTE_ID")

if [ "$PDF_QUOTE_ID" != "null" ] && [ ! -z "$PDF_QUOTE_ID" ]; then
  print_success "Quote created: $PDF_QUOTE_ID"
  
  print_test "Generating English PDF..."
  PDF_RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
    -H 'Content-Type: application/json' \
    -d '{
      "userId": "e2e_pdf_user",
      "locale": "en"
    }')
  
  PDF_URL=$(echo "$PDF_RESPONSE" | jq -r '.pdfUrl')
  PDF_CACHED=$(echo "$PDF_RESPONSE" | jq -r '.cached')
  PDF_TTL=$(echo "$PDF_RESPONSE" | jq -r '.ttlSeconds')
  
  if [ "$PDF_URL" != "null" ] && [ ! -z "$PDF_URL" ]; then
    print_success "PDF generated successfully"
    
    if [ "$PDF_CACHED" = "false" ]; then
      print_success "PDF was freshly generated (cached: false)"
    else
      print_error "Expected fresh PDF but got cached: $PDF_CACHED"
    fi
    
    if [ "$PDF_TTL" = "604800" ]; then
      print_success "PDF TTL is 7 days (604800 seconds)"
    else
      print_error "Expected TTL 604800 but got: $PDF_TTL"
    fi
    
    # Extract S3 key from presigned URL
    PDF_S3_KEY=$(echo "$PDF_URL" | sed 's/.*\.amazonaws\.com\/\([^?]*\).*/\1/')
    
    # Verify PDF exists in S3
    if aws s3api head-object --bucket "$PDF_BUCKET" --key "$PDF_S3_KEY" --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
      print_success "PDF exists in S3: $PDF_S3_KEY"
    else
      print_error "PDF not found in S3"
    fi
  else
    print_error "Failed to generate PDF"
  fi
else
  print_error "Failed to create quote for PDF test"
fi

# ========================================
# Test 16: PDF Caching (No Regeneration)
# ========================================
print_header "Test 16: PDF Caching (No Regeneration)"

if [ ! -z "$PDF_QUOTE_ID" ] && [ "$PDF_QUOTE_ID" != "null" ]; then
  print_test "Fetching quote to get PDF metadata before second request..."
  QUOTE_BEFORE=$(curl -s "$API_ENDPOINT/quotes/$PDF_QUOTE_ID")
  HASH_BEFORE=$(echo "$QUOTE_BEFORE" | jq -r '.lastPdfHash')
  S3_KEY_BEFORE=$(echo "$QUOTE_BEFORE" | jq -r '.pdfS3Key')
  
  if [ ! -z "$HASH_BEFORE" ] && [ "$HASH_BEFORE" != "null" ]; then
    print_success "Quote has lastPdfHash: ${HASH_BEFORE:0:16}..."
  else
    print_error "Quote missing lastPdfHash"
  fi
  
  # Wait a moment to ensure any timing-based issues are avoided
  sleep 1
  
  print_test "Requesting PDF again (should use cache)..."
  PDF_RESPONSE_2=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
    -H 'Content-Type: application/json' \
    -d '{
      "userId": "e2e_pdf_user",
      "locale": "en"
    }')
  
  PDF_CACHED_2=$(echo "$PDF_RESPONSE_2" | jq -r '.cached')
  
  if [ "$PDF_CACHED_2" = "true" ]; then
    print_success "PDF served from cache (cached: true)"
  else
    print_error "Expected cached PDF but got cached: $PDF_CACHED_2"
  fi
  
  print_test "Verifying hash hasn't changed..."
  QUOTE_AFTER=$(curl -s "$API_ENDPOINT/quotes/$PDF_QUOTE_ID")
  HASH_AFTER=$(echo "$QUOTE_AFTER" | jq -r '.lastPdfHash')
  S3_KEY_AFTER=$(echo "$QUOTE_AFTER" | jq -r '.pdfS3Key')
  
  if [ "$HASH_BEFORE" = "$HASH_AFTER" ]; then
    print_success "Hash unchanged (cache working correctly)"
  else
    print_error "Hash changed unexpectedly: $HASH_BEFORE -> $HASH_AFTER"
  fi
  
  if [ "$S3_KEY_BEFORE" = "$S3_KEY_AFTER" ]; then
    print_success "S3 key unchanged (no regeneration)"
  else
    print_error "S3 key changed: $S3_KEY_BEFORE -> $S3_KEY_AFTER"
  fi
else
  print_error "Skipping cache test (no PDF quote ID)"
fi

# ========================================
# Test 17: PDF Cache Ignores Status Changes
# ========================================
print_header "Test 17: PDF Cache Ignores Status Changes"

if [ ! -z "$PDF_QUOTE_ID" ] && [ "$PDF_QUOTE_ID" != "null" ]; then
  print_test "Getting hash before status change..."
  QUOTE_BEFORE_STATUS=$(curl -s "$API_ENDPOINT/quotes/$PDF_QUOTE_ID")
  HASH_BEFORE_STATUS=$(echo "$QUOTE_BEFORE_STATUS" | jq -r '.lastPdfHash')
  
  print_test "Updating quote status to 'sent'..."
  UPDATE_STATUS_RESPONSE=$(curl -s -X PUT "$API_ENDPOINT/quotes/$PDF_QUOTE_ID" \
    -H 'Content-Type: application/json' \
    -d '{
      "status": "sent"
    }')
  
  UPDATED_STATUS=$(echo "$UPDATE_STATUS_RESPONSE" | jq -r '.status')
  
  if [ "$UPDATED_STATUS" = "sent" ]; then
    print_success "Status updated to 'sent'"
    
    print_test "Generating PDF after status change (should use cache)..."
    PDF_RESPONSE_STATUS=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
      -H 'Content-Type: application/json' \
      -d '{
        "userId": "e2e_pdf_user",
        "locale": "en"
      }')
    
    PDF_CACHED_STATUS=$(echo "$PDF_RESPONSE_STATUS" | jq -r '.cached')
    
    if [ "$PDF_CACHED_STATUS" = "true" ]; then
      print_success "PDF served from cache after status change (cached: true)"
    else
      print_error "Expected cached PDF after status change but got cached: $PDF_CACHED_STATUS"
    fi
    
    print_test "Verifying hash unchanged after status change..."
    QUOTE_AFTER_STATUS=$(curl -s "$API_ENDPOINT/quotes/$PDF_QUOTE_ID")
    HASH_AFTER_STATUS=$(echo "$QUOTE_AFTER_STATUS" | jq -r '.lastPdfHash')
    
    if [ "$HASH_BEFORE_STATUS" = "$HASH_AFTER_STATUS" ]; then
      print_success "Hash unchanged after status change (status excluded from hash)"
    else
      print_error "Hash changed after status change: $HASH_BEFORE_STATUS -> $HASH_AFTER_STATUS"
    fi
  else
    print_error "Failed to update quote status"
  fi
else
  print_error "Skipping status change test (no PDF quote ID)"
fi

# ========================================
# Test 18: PDF Regeneration on Content Change
# ========================================
print_header "Test 18: PDF Regeneration on Content Change"

if [ ! -z "$PDF_QUOTE_ID" ] && [ "$PDF_QUOTE_ID" != "null" ]; then
  print_test "Updating quote content (should invalidate cache)..."
  UPDATE_RESPONSE=$(curl -s -X PUT "$API_ENDPOINT/quotes/$PDF_QUOTE_ID" \
    -H 'Content-Type: application/json' \
    -d '{
      "notes": "Updated: Customer needs work done urgently by Friday"
    }')
  
  UPDATED_NOTES=$(echo "$UPDATE_RESPONSE" | jq -r '.notes')
  
  if [[ "$UPDATED_NOTES" == *"Friday"* ]]; then
    print_success "Quote updated successfully"
    
    print_test "Generating PDF after content change..."
    PDF_RESPONSE_3=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
      -H 'Content-Type: application/json' \
      -d '{
        "userId": "e2e_pdf_user",
        "locale": "en"
      }')
    
    PDF_CACHED_3=$(echo "$PDF_RESPONSE_3" | jq -r '.cached')
    
    if [ "$PDF_CACHED_3" = "false" ]; then
      print_success "PDF regenerated after content change (cached: false)"
    else
      print_error "Expected fresh PDF after content change but got cached: $PDF_CACHED_3"
    fi
    
    print_test "Verifying hash changed..."
    QUOTE_UPDATED=$(curl -s "$API_ENDPOINT/quotes/$PDF_QUOTE_ID")
    HASH_UPDATED=$(echo "$QUOTE_UPDATED" | jq -r '.lastPdfHash')
    
    if [ "$HASH_BEFORE" != "$HASH_UPDATED" ]; then
      print_success "Hash changed after content update (cache invalidated)"
    else
      print_error "Hash should have changed but remained: $HASH_UPDATED"
    fi
  else
    print_error "Failed to update quote"
  fi
else
  print_error "Skipping regeneration test (no PDF quote ID)"
fi

# ========================================
# Test 19: Generate PDF (Spanish)
# ========================================
print_header "Test 19: Generate PDF (Spanish)"

if [ ! -z "$PDF_QUOTE_ID" ] && [ "$PDF_QUOTE_ID" != "null" ]; then
  print_test "Generating Spanish PDF..."
  PDF_RESPONSE_ES=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
    -H 'Content-Type: application/json' \
    -d '{
      "userId": "e2e_pdf_user",
      "locale": "es"
    }')
  
  PDF_URL_ES=$(echo "$PDF_RESPONSE_ES" | jq -r '.pdfUrl')
  
  if [ "$PDF_URL_ES" != "null" ] && [ ! -z "$PDF_URL_ES" ]; then
    print_success "Spanish PDF generated successfully"
    
    # Verify the URL is different from English (different presigned URL)
    if [ "$PDF_URL_ES" != "$PDF_URL" ]; then
      print_success "Spanish PDF has unique presigned URL"
    else
      print_error "Spanish PDF URL same as English (unexpected)"
    fi
  else
    print_error "Failed to generate Spanish PDF"
  fi
else
  print_error "Skipping Spanish PDF test (no PDF quote ID)"
fi

# ========================================
# Test 20: Locale-Specific PDF Caching
# ========================================
print_header "Test 20: Locale-Specific PDF Caching"

if [ ! -z "$PDF_QUOTE_ID" ] && [ "$PDF_QUOTE_ID" != "null" ]; then
  print_test "Verifying English and Spanish PDFs are cached independently..."
  
  # Get the quote to check stored PDF keys
  QUOTE_CHECK=$(curl -s "$API_ENDPOINT/quotes/$PDF_QUOTE_ID")
  PDF_KEY_EN=$(echo "$QUOTE_CHECK" | jq -r '.pdfS3KeyEn // empty')
  PDF_KEY_ES=$(echo "$QUOTE_CHECK" | jq -r '.pdfS3KeyEs // empty')
  LAST_HASH=$(echo "$QUOTE_CHECK" | jq -r '.lastPdfHash // empty')
  
  # Verify both locale-specific keys exist
  if [ ! -z "$PDF_KEY_EN" ] && [ "$PDF_KEY_EN" != "null" ]; then
    print_success "English PDF key exists: pdfS3KeyEn"
  else
    print_error "English PDF key (pdfS3KeyEn) not found in quote"
  fi
  
  if [ ! -z "$PDF_KEY_ES" ] && [ "$PDF_KEY_ES" != "null" ]; then
    print_success "Spanish PDF key exists: pdfS3KeyEs"
  else
    print_error "Spanish PDF key (pdfS3KeyEs) not found in quote"
  fi
  
  # Verify keys are different
  if [ "$PDF_KEY_EN" != "$PDF_KEY_ES" ]; then
    print_success "Locale-specific keys are different"
  else
    print_error "Locale keys should be different but are the same"
  fi
  
  # Verify English key has _en suffix
  if echo "$PDF_KEY_EN" | grep -q "_en\.pdf"; then
    print_success "English PDF key has _en suffix"
  else
    print_error "English PDF key missing _en suffix: $PDF_KEY_EN"
  fi
  
  # Verify Spanish key has _es suffix
  if echo "$PDF_KEY_ES" | grep -q "_es\.pdf"; then
    print_success "Spanish PDF key has _es suffix"
  else
    print_error "Spanish PDF key missing _es suffix: $PDF_KEY_ES"
  fi
  
  # Verify shared content hash
  if [ ! -z "$LAST_HASH" ] && [ "$LAST_HASH" != "null" ]; then
    print_success "Content hash (lastPdfHash) is stored and shared across locales"
  else
    print_error "Content hash (lastPdfHash) not found"
  fi
  
  # Request English again - should be cached
  print_test "Requesting English PDF again (should be cached)..."
  PDF_EN_CACHED=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
    -H 'Content-Type: application/json' \
    -d '{
      "userId": "e2e_pdf_user",
      "locale": "en"
    }')
  
  EN_CACHED=$(echo "$PDF_EN_CACHED" | jq -r '.cached')
  if [ "$EN_CACHED" = "true" ]; then
    print_success "English PDF served from cache"
  else
    print_error "English PDF not cached (expected cached: true, got: $EN_CACHED)"
  fi
  
  # Request Spanish again - should also be cached
  print_test "Requesting Spanish PDF again (should be cached)..."
  PDF_ES_CACHED=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
    -H 'Content-Type: application/json' \
    -d '{
      "userId": "e2e_pdf_user",
      "locale": "es"
    }')
  
  ES_CACHED=$(echo "$PDF_ES_CACHED" | jq -r '.cached')
  if [ "$ES_CACHED" = "true" ]; then
    print_success "Spanish PDF served from cache"
  else
    print_error "Spanish PDF not cached (expected cached: true, got: $ES_CACHED)"
  fi
  
  # Verify URLs are different (different S3 keys)
  EN_URL=$(echo "$PDF_EN_CACHED" | jq -r '.pdfUrl')
  ES_URL=$(echo "$PDF_ES_CACHED" | jq -r '.pdfUrl')
  
  if [ "$EN_URL" != "$ES_URL" ]; then
    print_success "English and Spanish PDFs have different URLs (different S3 keys)"
  else
    print_error "English and Spanish PDFs have the same URL (should be different)"
  fi
  
  # Extract S3 keys from URLs to verify they match DynamoDB fields
  EN_URL_KEY=$(echo "$EN_URL" | sed 's/.*\.amazonaws\.com\/\([^?]*\).*/\1/')
  ES_URL_KEY=$(echo "$ES_URL" | sed 's/.*\.amazonaws\.com\/\([^?]*\).*/\1/')
  
  if [ "$EN_URL_KEY" = "$PDF_KEY_EN" ]; then
    print_success "English URL matches pdfS3KeyEn field"
  else
    print_error "English URL key mismatch: URL=$EN_URL_KEY, DB=$PDF_KEY_EN"
  fi
  
  if [ "$ES_URL_KEY" = "$PDF_KEY_ES" ]; then
    print_success "Spanish URL matches pdfS3KeyEs field"
  else
    print_error "Spanish URL key mismatch: URL=$ES_URL_KEY, DB=$PDF_KEY_ES"
  fi
  
else
  print_error "Skipping locale-specific caching test (no PDF quote ID)"
fi

# ========================================
# Test 21: Force PDF Regeneration
# ========================================
print_header "Test 21: Force PDF Regeneration"

# ========================================
# Test 21: Force PDF Regeneration
# ========================================
print_header "Test 21: Force PDF Regeneration"

if [ ! -z "$PDF_QUOTE_ID" ] && [ "$PDF_QUOTE_ID" != "null" ]; then
  print_test "Forcing PDF regeneration with forceRegenerate flag..."
  PDF_RESPONSE_FORCE=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
    -H 'Content-Type: application/json' \
    -d '{
      "userId": "e2e_pdf_user",
      "locale": "en",
      "forceRegenerate": true
    }')
  
  PDF_CACHED_FORCE=$(echo "$PDF_RESPONSE_FORCE" | jq -r '.cached')
  
  if [ "$PDF_CACHED_FORCE" = "false" ]; then
    print_success "PDF regenerated with forceRegenerate flag"
  else
    print_error "Expected fresh PDF with forceRegenerate but got cached: $PDF_CACHED_FORCE"
  fi
else
  print_error "Skipping force regeneration test (no PDF quote ID)"
fi

# ========================================
# Test 22: PDF Cleanup on Quote Deletion
# ========================================
print_header "Test 22: PDF Cleanup on Quote Deletion"

print_test "Creating quote with PDF for deletion test..."
RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "e2e_pdf_delete_user",
    "customerName": "PDF Delete Test",
    "customerPhone": "555-DEL1",
    "customerAddress": "789 Delete Ave",
    "items": [
      {
        "type": "cleanup",
        "description": "Test cleanup",
        "price": 10000
      }
    ]
  }')

PDF_DELETE_QUOTE_ID=$(echo "$RESPONSE" | jq -r '.quoteId')

if [ "$PDF_DELETE_QUOTE_ID" != "null" ] && [ ! -z "$PDF_DELETE_QUOTE_ID" ]; then
  print_success "Quote created: $PDF_DELETE_QUOTE_ID"
  
  print_test "Generating PDF for deletion test..."
  PDF_RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_DELETE_QUOTE_ID/pdf" \
    -H 'Content-Type: application/json' \
    -d '{
      "userId": "e2e_pdf_delete_user",
      "locale": "en"
    }')
  
  PDF_S3_KEY_DELETE=$(echo "$PDF_RESPONSE" | jq -r '.pdfUrl' | sed 's/.*\.amazonaws\.com\/\([^?]*\).*/\1/')
  
  if [ ! -z "$PDF_S3_KEY_DELETE" ] && [ "$PDF_S3_KEY_DELETE" != "null" ]; then
    print_success "PDF generated with S3 key: $PDF_S3_KEY_DELETE"
    
    # Verify PDF exists before deletion
    if aws s3api head-object --bucket "$PDF_BUCKET" --key "$PDF_S3_KEY_DELETE" --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
      print_success "PDF exists in S3 before deletion"
      
      print_test "Deleting quote (should also delete PDF)..."
      DELETE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$API_ENDPOINT/quotes/$PDF_DELETE_QUOTE_ID")
      
      if [ "$DELETE_STATUS" = "204" ]; then
        print_success "Quote deleted (HTTP 204)"
        
        # Wait a moment for S3 cleanup
        sleep 2
        
        # Verify PDF is deleted
        if ! aws s3api head-object --bucket "$PDF_BUCKET" --key "$PDF_S3_KEY_DELETE" --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
          print_success "PDF deleted from S3"
        else
          print_error "PDF still exists in S3 after quote deletion"
        fi
      else
        print_error "Failed to delete quote (HTTP $DELETE_STATUS)"
      fi
    else
      print_error "PDF not found in S3 before deletion test"
    fi
  else
    print_error "Failed to extract S3 key from PDF URL"
  fi
else
  print_error "Failed to create quote for PDF deletion test"
fi

# ========================================
# Test 23: PDF with Missing userId (Validation)
# ========================================
print_header "Test 23: PDF with Missing userId (Validation)"

if [ ! -z "$PDF_QUOTE_ID" ] && [ "$PDF_QUOTE_ID" != "null" ]; then
  print_test "Attempting to generate PDF without userId..."
  PDF_ERROR_RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
    -H 'Content-Type: application/json' \
    -d '{
      "locale": "en"
    }')
  
  PDF_ERROR=$(echo "$PDF_ERROR_RESPONSE" | jq -r '.error')
  
  if [ "$PDF_ERROR" = "ValidationError" ] || [[ "$PDF_ERROR_RESPONSE" == *"userId"* ]]; then
    print_success "Missing userId validation working"
  else
    print_error "Expected validation error but got: $PDF_ERROR_RESPONSE"
  fi
else
  print_error "Skipping validation test (no PDF quote ID)"
fi

# ========================================
# Test 24: PDF with Wrong User (Ownership)
# ========================================
print_header "Test 24: PDF with Wrong User (Ownership)"

if [ ! -z "$PDF_QUOTE_ID" ] && [ "$PDF_QUOTE_ID" != "null" ]; then
  print_test "Attempting to generate PDF with wrong userId..."
  PDF_FORBIDDEN_RESPONSE=$(curl -s -X POST "$API_ENDPOINT/quotes/$PDF_QUOTE_ID/pdf" \
    -H 'Content-Type: application/json' \
    -d '{
      "userId": "wrong_user_123",
      "locale": "en"
    }')
  
  PDF_FORBIDDEN_ERROR=$(echo "$PDF_FORBIDDEN_RESPONSE" | jq -r '.error')
  
  if [ "$PDF_FORBIDDEN_ERROR" = "Forbidden" ] || [[ "$PDF_FORBIDDEN_RESPONSE" == *"not belong"* ]]; then
    print_success "Ownership validation working"
  else
    print_error "Expected forbidden error but got: $PDF_FORBIDDEN_RESPONSE"
  fi
else
  print_error "Skipping ownership test (no PDF quote ID)"
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

