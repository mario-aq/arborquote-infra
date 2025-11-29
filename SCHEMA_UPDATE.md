# Schema Migration Summary

## Multi-Item Quote Schema Update

**Date:** November 29, 2025  
**Status:** ✅ Complete - Ready for deployment

---

## What Changed

The quote schema has been updated from a **single-job structure** to a **multi-item structure** to support multiple trees or tasks per quote.

### Before (Old Schema)

```json
{
  "quoteId": "01HQXYZ...",
  "userId": "user_001",
  "customerName": "John Doe",
  "jobType": "tree removal",           // ❌ Single job only
  "photos": [...],                      // ❌ Photos at top level
  "price": 50000,                       // ❌ Single price
  "status": "draft",
  ...
}
```

### After (New Schema)

```json
{
  "quoteId": "01HQXYZ...",
  "userId": "user_001",
  "customerName": "John Doe",
  "items": [                            // ✅ Multiple items
    {
      "itemId": "01HQXYZITEM1...",
      "type": "tree_removal",           // ✅ Type per item
      "description": "Large oak tree",
      "diameterInInches": 36,
      "heightInFeet": 45,
      "riskFactors": ["near_structure"],
      "price": 85000,                   // ✅ Price per item
      "photos": [...]                   // ✅ Photos per item
    },
    {
      "itemId": "01HQXYZITEM2...",
      "type": "stump_grinding",
      "description": "Grind stump",
      "price": 25000
    }
  ],
  "totalPrice": 110000,                 // ✅ Auto-calculated total
  "status": "draft",
  ...
}
```

---

## Breaking Changes

Since this hasn't been deployed yet, these are **clean breaking changes** (no migration needed):

### Removed Fields
- ❌ `jobType` (top-level) → Use `items[].type` instead
- ❌ `photos` (top-level) → Use `items[].photos` instead
- ❌ `price` (top-level) → Use `totalPrice` (auto-calculated)

### New Required Fields
- ✅ `items` (array, min 1 item) - Each item must have:
  - `type` (string, enum)
  - `description` (string)
  - Optional: `diameterInInches`, `heightInFeet`, `riskFactors`, `price`, `photos`

### New Auto-Generated Fields
- ✅ `itemId` - ULID for each item (generated server-side)
- ✅ `totalPrice` - Sum of all item prices (calculated server-side)

---

## Item Types (Enum)

Valid values for `item.type`:
- `tree_removal` - Complete tree removal
- `pruning` - Tree pruning/trimming
- `stump_grinding` - Stump removal
- `cleanup` - Debris removal and cleanup
- `trimming` - Light trimming work
- `emergency_service` - Emergency tree services
- `other` - Other services

---

## Updated Files

### Lambda Handlers
- ✅ `lambda/create_quote/handler.rb` - Accepts items array, generates itemIds, calculates totalPrice
- ✅ `lambda/update_quote/handler.rb` - Updates items array, recalculates totalPrice
- ⚪ `lambda/get_quote/handler.rb` - No changes (returns full object)
- ⚪ `lambda/list_quotes/handler.rb` - No changes

### Shared Utilities
- ✅ `lambda/shared/db_client.rb` - Added:
  - `ValidationHelper.validate_items()` - Validates items array
  - `ValidationHelper.validate_item()` - Validates individual item
  - `ValidationHelper.validate_item_type()` - Validates item type enum
  - `ItemHelper.build_item()` - Builds item with generated itemId
  - `ItemHelper.calculate_total_price()` - Calculates sum of item prices

### Documentation
- ✅ `README.md` - Updated data model section with new schema
- ✅ `API_EXAMPLES.md` - Updated all examples with multi-item requests/responses

### Infrastructure
- ⚪ No CDK changes needed (DynamoDB supports nested structures)

---

## Example API Requests

### Create Quote with Multiple Items

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
  }'
```

### Update Quote Items

```bash
curl -X PUT $API_ENDPOINT/quotes/01HQXYZ... \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {
        "itemId": "01HQXYZITEM1...",
        "type": "tree_removal",
        "description": "Large oak tree",
        "price": 95000
      },
      {
        "type": "cleanup",
        "description": "Haul away debris",
        "price": 15000
      }
    ]
  }'
```

**Note:** Items with `itemId` are updated, items without are added as new.

---

## Validation Rules

### Quote Level
- ✅ `items` array is required
- ✅ Must have at least 1 item
- ✅ `totalPrice` is auto-calculated (ignores client input)

### Item Level
- ✅ `type` is required (must be valid enum value)
- ✅ `description` is required
- ✅ `price` must be non-negative integer (cents)
- ✅ `diameterInInches` must be positive number (if provided)
- ✅ `heightInFeet` must be positive number (if provided)
- ✅ `riskFactors` must be array (if provided)
- ✅ `photos` must be array (if provided)

---

## Testing

### Manual Testing

1. **Create quote with items:**
   ```bash
   export API_ENDPOINT="your_api_endpoint"
   curl -X POST $API_ENDPOINT/quotes -H "Content-Type: application/json" -d '...'
   ```

2. **Verify totalPrice calculation:**
   - Check that `totalPrice` equals sum of all `items[].price`

3. **Test item validation:**
   - Try invalid item type → Should get 400 error
   - Try empty items array → Should get 400 error
   - Try missing description → Should get 400 error

4. **Test update:**
   - Update existing item (with itemId) → Should preserve itemId
   - Add new item (without itemId) → Should generate new itemId
   - Verify totalPrice recalculates

### Automated Testing

See `API_EXAMPLES.md` for the `test_api.sh` script that tests all CRUD operations with the new schema.

---

## Deployment

No special deployment steps needed. Just deploy as normal:

```bash
npm run build
cdk deploy --profile arborquote
```

The new schema takes effect immediately upon deployment.

---

## Backwards Compatibility

**Not applicable** - This system has not been deployed or used yet, so there's no existing data to migrate.

---

## Future Enhancements

Possible future improvements:
- [ ] Add item-level status tracking (e.g., "completed", "in_progress")
- [ ] Support for item-level scheduling/dates
- [ ] Item templates for common tree types/services
- [ ] Bulk item import from CSV
- [ ] Item-level discounts or adjustments

---

## Questions?

See:
- `README.md` - Full architecture documentation
- `API_EXAMPLES.md` - Complete API reference with examples
- `QUICKSTART.md` - Quick deployment guide

CloudWatch logs:
```bash
aws logs tail /aws/lambda/ArborQuote-CreateQuote-dev --follow --profile arborquote
```

