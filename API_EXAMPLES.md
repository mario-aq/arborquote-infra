# ArborQuote API Examples

Quick reference for testing the ArborQuote API endpoints.

## Setup

After deploying the stack, save your API endpoint:

```bash
export API_ENDPOINT="https://YOUR_API_ID.execute-api.REGION.amazonaws.com"
```

Replace `YOUR_API_ID` and `REGION` with the values from the CDK deployment output.

## API Examples

### 1. Create a Quote

**Request:**
```bash
curl -X POST $API_ENDPOINT/quotes \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_001",
    "customerName": "John Doe",
    "customerPhone": "555-1234",
    "customerAddress": "123 Oak Street, Springfield, IL 62701",
    "items": [
      {
        "type": "tree_removal",
        "description": "Large oak tree in backyard, leaning toward house",
        "diameterInInches": 36,
        "heightInFeet": 45,
        "riskFactors": ["near_structure", "leaning"],
        "price": 85000,
        "photos": []
      },
      {
        "type": "stump_grinding",
        "description": "Grind remaining stump from oak removal",
        "diameterInInches": 36,
        "price": 25000,
        "photos": []
      },
      {
        "type": "cleanup",
        "description": "Haul away debris and wood chips",
        "price": 15000,
        "photos": []
      }
    ],
    "notes": "Customer wants work completed before winter. Will need crane access from street."
  }'
```

**Response (201 Created):**
```json
{
  "quoteId": "01HQXYZ9ABC...",
  "userId": "user_001",
  "customerName": "John Doe",
  "customerPhone": "555-1234",
  "customerAddress": "123 Oak Street, Springfield, IL 62701",
  "status": "draft",
  "items": [
    {
      "itemId": "01HQXYZITEM1...",
      "type": "tree_removal",
      "description": "Large oak tree in backyard, leaning toward house",
      "diameterInInches": 36,
      "heightInFeet": 45,
      "riskFactors": ["near_structure", "leaning"],
      "price": 85000,
      "photos": []
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
    },
    {
      "itemId": "01HQXYZITEM3...",
      "type": "cleanup",
      "description": "Haul away debris and wood chips",
      "diameterInInches": null,
      "heightInFeet": null,
      "riskFactors": [],
      "price": 15000,
      "photos": []
    }
  ],
  "totalPrice": 125000,
  "notes": "Customer wants work completed before winter. Will need crane access from street.",
  "createdAt": "2025-11-29T14:30:00.123Z",
  "updatedAt": "2025-11-29T14:30:00.123Z"
}
```

### 2. List All Quotes for a User

**Request:**
```bash
curl "$API_ENDPOINT/quotes?userId=user_001"
```

**Response (200 OK):**
```json
{
  "quotes": [
    {
      "quoteId": "01HQXYZ9ABC...",
      "customerName": "John Doe",
      "status": "draft",
      "totalPrice": 125000,
      "items": [...],
      "createdAt": "2025-11-29T14:30:00.123Z",
      ...
    },
    {
      "quoteId": "01HQXYZ8DEF...",
      "customerName": "Jane Smith",
      "status": "sent",
      "totalPrice": 35000,
      "items": [...],
      "createdAt": "2025-11-28T10:15:00.456Z",
      ...
    }
    }
  ],
  "count": 2,
  "userId": "user_001"
}
```

### 3. Get a Specific Quote

**Request:**
```bash
curl "$API_ENDPOINT/quotes/01HQXYZ9ABC..."
```

**Response (200 OK):**
```json
{
  "quoteId": "01HQXYZ9ABC...",
  "userId": "user_001",
  "customerName": "John Doe",
  "customerPhone": "555-1234",
  "customerAddress": "123 Oak Street, Springfield, IL 62701",
  "status": "draft",
  "items": [
    {
      "itemId": "01HQXYZITEM1...",
      "type": "tree_removal",
      "description": "Large oak tree in backyard, leaning toward house",
      "diameterInInches": 36,
      "heightInFeet": 45,
      "riskFactors": ["near_structure", "leaning"],
      "price": 85000,
      "photos": []
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
  "totalPrice": 110000,
  "notes": "Customer wants work completed before winter.",
  "createdAt": "2025-11-29T14:30:00.123Z",
  "updatedAt": "2025-11-29T14:30:00.123Z"
}
```

### 4. Update a Quote

**Update items and status:**
```bash
curl -X PUT $API_ENDPOINT/quotes/01HQXYZ9ABC... \
  -H "Content-Type: application/json" \
  -d '{
    "status": "sent",
    "items": [
      {
        "itemId": "01HQXYZITEM1...",
        "type": "tree_removal",
        "description": "Large oak tree in backyard, leaning toward house",
        "diameterInInches": 36,
        "heightInFeet": 45,
        "riskFactors": ["near_structure", "leaning"],
        "price": 95000,
        "photos": []
      },
      {
        "itemId": "01HQXYZITEM2...",
        "type": "stump_grinding",
        "description": "Grind remaining stump from oak removal",
        "diameterInInches": 36,
        "price": 30000,
        "photos": []
      }
    ],
    "notes": "Updated pricing after site inspection. Customer approved."
  }'
```

**Response (200 OK):**
```json
{
  "quoteId": "01HQXYZ9ABC...",
  "userId": "user_001",
  "customerName": "John Doe",
  "customerPhone": "555-1234",
  "customerAddress": "123 Oak Street, Springfield, IL 62701",
  "status": "sent",
  "items": [
    {
      "itemId": "01HQXYZITEM1...",
      "type": "tree_removal",
      "description": "Large oak tree in backyard, leaning toward house",
      "diameterInInches": 36,
      "heightInFeet": 45,
      "riskFactors": ["near_structure", "leaning"],
      "price": 95000,
      "photos": []
    },
    {
      "itemId": "01HQXYZITEM2...",
      "type": "stump_grinding",
      "description": "Grind remaining stump from oak removal",
      "diameterInInches": 36,
      "heightInFeet": null,
      "riskFactors": [],
      "price": 30000,
      "photos": []
    }
  ],
  "totalPrice": 125000,
  "notes": "Updated pricing after site inspection. Customer approved.",
  "createdAt": "2025-11-29T14:30:00.123Z",
  "updatedAt": "2025-11-29T15:45:00.789Z"
}
```

## Common Use Cases

### Create a Simple Quote (Single Item)

```bash
curl -X POST $API_ENDPOINT/quotes \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_001",
    "customerName": "Alice Johnson",
    "customerPhone": "555-9876",
    "customerAddress": "456 Pine Avenue",
    "items": [
      {
        "type": "pruning",
        "description": "Trim maple tree branches overhanging driveway",
        "heightInFeet": 25,
        "price": 35000
      }
    ]
  }'
```

The status will default to `"draft"` and totalPrice will be auto-calculated.

### Update Only the Status

```bash
curl -X PUT $API_ENDPOINT/quotes/01HQXYZ9ABC... \
  -H "Content-Type: application/json" \
  -d '{"status": "accepted"}'
```

You can update individual fields - only provided fields will be changed.

### Search for Quotes

Currently, you can list quotes by `userId`:

```bash
curl "$API_ENDPOINT/quotes?userId=user_001"
```

## Error Responses

### 400 Bad Request - Missing Required Fields

**Request:**
```bash
curl -X POST $API_ENDPOINT/quotes \
  -H "Content-Type: application/json" \
  -d '{"userId": "user_001"}'
```

**Response:**
```json
{
  "error": "ValidationError",
  "message": "Missing required fields: customerName, customerPhone, customerAddress"
}
```

### 400 Bad Request - Missing Items

**Request:**
```bash
curl -X POST $API_ENDPOINT/quotes \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_001",
    "customerName": "John Doe",
    "customerPhone": "555-1234",
    "customerAddress": "123 Oak St",
    "items": []
  }'
```

**Response:**
```json
{
  "error": "ValidationError",
  "message": "Quote must have at least one item"
}
```

### 400 Bad Request - Invalid Item Type

**Request:**
```bash
curl -X POST $API_ENDPOINT/quotes \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_001",
    "customerName": "John Doe",
    "customerPhone": "555-1234",
    "customerAddress": "123 Oak St",
    "items": [
      {
        "type": "invalid_type",
        "description": "Test",
        "price": 1000
      }
    ]
  }'
```

**Response:**
```json
{
  "error": "ValidationError",
  "message": "Invalid item type. Must be one of: tree_removal, pruning, stump_grinding, cleanup, trimming, emergency_service, other"
}
```

### 400 Bad Request - Invalid Status

**Request:**
```bash
curl -X PUT $API_ENDPOINT/quotes/01HQXYZ9ABC... \
  -H "Content-Type: application/json" \
  -d '{"status": "invalid_status"}'
```

**Response:**
```json
{
  "error": "ValidationError",
  "message": "Invalid status. Must be one of: draft, sent, accepted, rejected"
}
```

### 404 Not Found - Quote Doesn't Exist

**Request:**
```bash
curl "$API_ENDPOINT/quotes/INVALID_ID"
```

**Response:**
```json
{
  "error": "QuoteNotFound",
  "message": "Quote with ID INVALID_ID not found"
}
```

### 500 Internal Server Error

**Response:**
```json
{
  "error": "InternalServerError",
  "message": "An unexpected error occurred"
}
```

Check CloudWatch logs for details:
```bash
aws logs tail /aws/lambda/ArborQuote-CreateQuote-dev --follow --profile arborquote
```

## Field Reference

### Quote Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `quoteId` | String | Auto-generated | ULID identifier (time-sortable) |
| `userId` | String | Yes | User who created the quote |
| `customerName` | String | Yes | Customer's full name |
| `customerPhone` | String | Yes | Customer's phone number |
| `customerAddress` | String | Yes | Job site address |
| `items` | Array | Yes | Array of quote line items (min 1 item) |
| `totalPrice` | Number | Auto-calculated | Sum of all item prices (cents) |
| `notes` | String | No | Additional notes or details |
| `status` | String | No | Quote status: "draft", "sent", "accepted", "rejected" |
| `createdAt` | String | Auto-generated | ISO 8601 timestamp |
| `updatedAt` | String | Auto-generated | ISO 8601 timestamp |

### Item Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | String | Auto-generated | ULID identifier for this item |
| `type` | String | Yes | Type of work (see Item Types below) |
| `description` | String | Yes | Detailed description of the work |
| `diameterInInches` | Number | No | Trunk diameter in inches |
| `heightInFeet` | Number | No | Tree height in feet |
| `riskFactors` | Array | No | Array of risk factor strings |
| `price` | Number | No | Price for this item in cents (default: 0) |
| `photos` | Array | No | Array of S3 URLs/keys for photos |

### Item Types

Valid values for `item.type`:
- `tree_removal` - Complete tree removal
- `pruning` - Tree pruning/trimming
- `stump_grinding` - Stump removal
- `cleanup` - Debris removal and cleanup
- `trimming` - Light trimming work
- `emergency_service` - Emergency tree services
- `other` - Other services

### Status Values

- `draft` - Quote is being prepared (default)
- `sent` - Quote has been sent to customer
- `accepted` - Customer accepted the quote
- `rejected` - Customer rejected the quote

### Price Format

Prices are stored in **cents** to avoid floating-point precision issues:

- $500.00 → `50000`
- $1,250.50 → `125050`
- $85.00 → `8500`

## Testing Script

Save this as `test_api.sh`:

```bash
#!/bin/bash

# Set your API endpoint
API_ENDPOINT="https://YOUR_API_ID.execute-api.REGION.amazonaws.com"

echo "=== Creating a quote ==="
QUOTE_RESPONSE=$(curl -s -X POST $API_ENDPOINT/quotes \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_test_001",
    "customerName": "Test Customer",
    "customerPhone": "555-0000",
    "customerAddress": "123 Test Street",
    "items": [
      {
        "type": "tree_removal",
        "description": "Test oak tree removal",
        "heightInFeet": 40,
        "price": 50000
      }
    ]
  }')

echo $QUOTE_RESPONSE | jq .

# Extract quoteId
QUOTE_ID=$(echo $QUOTE_RESPONSE | jq -r .quoteId)
echo ""
echo "Created quote with ID: $QUOTE_ID"

echo ""
echo "=== Getting the quote ==="
curl -s "$API_ENDPOINT/quotes/$QUOTE_ID" | jq .

echo ""
echo "=== Updating the quote ==="
curl -s -X PUT "$API_ENDPOINT/quotes/$QUOTE_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "sent",
    "items": [
      {
        "type": "tree_removal",
        "description": "Test oak tree removal",
        "heightInFeet": 40,
        "price": 60000
      }
    ]
  }' | jq .

echo ""
echo "=== Listing all quotes for user ==="
curl -s "$API_ENDPOINT/quotes?userId=user_test_001" | jq .
```

Make it executable and run:
```bash
chmod +x test_api.sh
./test_api.sh
```

**Note:** Requires `jq` for JSON formatting. Install with:
```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq
```

## Next Steps

1. Deploy the infrastructure: `cdk deploy --profile arborquote`
2. Save your API endpoint from the output
3. Run the examples above to test
4. Check CloudWatch logs if you encounter errors
5. Build your frontend to consume this API

