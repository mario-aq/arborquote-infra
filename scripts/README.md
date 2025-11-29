# ArborQuote Test Scripts

## E2E Test Suite

The `test-e2e.sh` script provides comprehensive end-to-end testing of the ArborQuote API.

### Running the Tests

```bash
# Run all tests with default settings
./scripts/test-e2e.sh

# Run with custom API endpoint
API_ENDPOINT=https://api.arborquote.app ./scripts/test-e2e.sh

# Run with custom AWS profile
AWS_PROFILE=myprofile ./scripts/test-e2e.sh

# Run with custom AWS region
AWS_REGION=us-west-2 ./scripts/test-e2e.sh
```

### Environment Variables

- `API_ENDPOINT` - API Gateway endpoint (default: `https://api-dev.arborquote.app`)
- `AWS_PROFILE` - AWS CLI profile to use (default: `arborquote`)
- `AWS_REGION` - AWS region (default: `us-east-1`)

### Test Coverage

The E2E test suite includes 14 comprehensive tests:

#### CRUD Operations
1. **Create Simple Quote** - Create quote without photos
2. **Create Quote with Base64 Photos** - Upload photos inline with quote creation
3. **Get Quote with Presigned URLs** - Retrieve quote and verify presigned URLs
4. **List Quotes** - List all quotes for a user
5. **Update Quote** - Update quote status and fields
6. **Add Photo to Existing Quote** - Update quote to add new photos
7. **Delete Quote** - Delete quote and verify photo cleanup

#### Photo Management
8. **Upload Photos Independently** - Use POST /photos endpoint
9. **Create Quote with S3 Keys** - Create quote using pre-uploaded photo keys
10. **Delete Individual Photo** - Use DELETE /photos endpoint
11. **Delete Quote with Photo Cleanup** - Verify S3 cleanup on quote deletion
12. **Remove Item from Quote** - Verify photos deleted when items removed

#### Validation
13. **Invalid Content Type** - Ensure invalid content types are rejected
14. **Too Many Photos per Item** - Enforce max 3 photos per item limit
15. **Missing Required Fields** - Validate required field enforcement

### S3 Path Verification

The tests verify that:
- Photos use `itemId` in S3 paths (not array index)
- Paths are stable regardless of item ordering
- Photos are properly cleaned up when items/quotes are deleted

### Test Output

The script provides colorized output:
- 🟢 Green checkmarks (✅) for passing tests
- 🔴 Red X marks (❌) for failing tests
- 🔵 Blue headers for test sections
- 🟡 Yellow for test descriptions

### Cleanup

The script automatically cleans up all test data on exit, including:
- Test quotes created during the run
- Photos uploaded to S3

### Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

### Requirements

- `curl` - For making HTTP requests
- `jq` - For JSON processing
- `aws` CLI - For S3 verification
- AWS credentials configured for the specified profile

