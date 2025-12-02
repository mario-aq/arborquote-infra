#!/bin/bash

# Test script for voice-interpret endpoint
# Usage: ./scripts/test-voice.sh [audio-file] [env]

set -e

# Configuration
AUDIO_FILE=${1:-"test-audio.webm"}
ENV=${2:-"dev"}
API_BASE="https://api-${ENV}.arborquote.app"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ArborQuote Voice Interpret Test ===${NC}"
echo ""

# Check if audio file exists
if [ ! -f "$AUDIO_FILE" ]; then
  echo -e "${RED}Error: Audio file not found: $AUDIO_FILE${NC}"
  echo "Usage: $0 <audio-file> [env]"
  echo "Example: $0 test-audio.webm dev"
  exit 1
fi

# Detect MIME type from file extension
EXTENSION="${AUDIO_FILE##*.}"
case $EXTENSION in
  webm)
    MIME_TYPE="audio/webm"
    ;;
  m4a)
    MIME_TYPE="audio/m4a"
    ;;
  mp4)
    MIME_TYPE="audio/mp4"
    ;;
  ogg)
    MIME_TYPE="audio/ogg"
    ;;
  wav)
    MIME_TYPE="audio/wav"
    ;;
  mp3)
    MIME_TYPE="audio/mpeg"
    ;;
  *)
    echo -e "${RED}Error: Unsupported audio format: $EXTENSION${NC}"
    echo "Supported: webm, m4a, mp4, ogg, wav, mp3"
    exit 1
    ;;
esac

echo -e "Audio file: ${GREEN}$AUDIO_FILE${NC}"
echo -e "MIME type: ${GREEN}$MIME_TYPE${NC}"
echo -e "Environment: ${GREEN}$ENV${NC}"
echo -e "API: ${GREEN}$API_BASE${NC}"
echo ""

# Get file size
FILE_SIZE=$(wc -c < "$AUDIO_FILE" | tr -d ' ')
echo -e "File size: ${GREEN}$FILE_SIZE bytes${NC}"

# Check if file is too large (5MB = 5242880 bytes)
if [ "$FILE_SIZE" -gt 5242880 ]; then
  echo -e "${RED}Warning: File may be too large (>5MB). Consider compressing or shortening.${NC}"
fi

# Encode to base64
echo -e "${BLUE}Encoding audio to base64...${NC}"
AUDIO_BASE64=$(base64 < "$AUDIO_FILE" | tr -d '\n')
BASE64_SIZE=${#AUDIO_BASE64}
echo -e "Base64 size: ${GREEN}$BASE64_SIZE bytes${NC}"

# Sample quote draft
QUOTE_DRAFT='{
  "status": "draft",
  "items": [
    {
      "itemId": "01HQXYZITEM1234567890001",
      "type": "tree_removal",
      "description": "Large oak tree in backyard",
      "price": 85000,
      "diameterInInches": 36,
      "heightInFeet": 45,
      "riskFactors": ["near_structure"],
      "photos": []
    },
    {
      "itemId": "01HQXYZITEM1234567890002",
      "type": "pruning",
      "description": "Maple tree trimming",
      "price": 45000,
      "heightInFeet": 30,
      "riskFactors": [],
      "photos": []
    }
  ],
  "totalPrice": 130000,
  "notes": ""
}'

# Build request payload
REQUEST_PAYLOAD=$(cat <<EOF
{
  "audioBase64": "$AUDIO_BASE64",
  "audioMimeType": "$MIME_TYPE",
  "quoteDraft": $QUOTE_DRAFT
}
EOF
)

# Make API request
echo ""
echo -e "${BLUE}Sending request to API...${NC}"
echo -e "Endpoint: ${GREEN}POST $API_BASE/quotes/voice-interpret${NC}"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/quotes/voice-interpret" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_PAYLOAD")

# Split response and status code
HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)

echo -e "HTTP Status: ${GREEN}$HTTP_CODE${NC}"
echo ""

# Check if successful
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ Success!${NC}"
  echo ""
  
  # Pretty print response
  echo -e "${BLUE}=== Transcript ===${NC}"
  echo "$HTTP_BODY" | jq -r '.transcript'
  echo ""
  
  echo -e "${BLUE}=== Detected Language ===${NC}"
  echo "$HTTP_BODY" | jq -r '.detectedLanguage'
  echo ""
  
  echo -e "${BLUE}=== Updated Quote Draft ===${NC}"
  echo "$HTTP_BODY" | jq '.updatedQuoteDraft'
  echo ""
  
  # Show price changes
  ORIGINAL_TOTAL=$(echo "$QUOTE_DRAFT" | jq '.totalPrice')
  NEW_TOTAL=$(echo "$HTTP_BODY" | jq '.updatedQuoteDraft.totalPrice')
  
  if [ "$ORIGINAL_TOTAL" != "$NEW_TOTAL" ]; then
    echo -e "${BLUE}=== Price Change ===${NC}"
    echo -e "Original: ${GREEN}\$$(echo "scale=2; $ORIGINAL_TOTAL / 100" | bc)${NC}"
    echo -e "Updated:  ${GREEN}\$$(echo "scale=2; $NEW_TOTAL / 100" | bc)${NC}"
    DIFF=$((NEW_TOTAL - ORIGINAL_TOTAL))
    if [ "$DIFF" -gt 0 ]; then
      echo -e "Change:   ${GREEN}+\$$(echo "scale=2; $DIFF / 100" | bc)${NC}"
    else
      echo -e "Change:   ${RED}\$$(echo "scale=2; $DIFF / 100" | bc)${NC}"
    fi
  fi
else
  echo -e "${RED}✗ Error!${NC}"
  echo ""
  echo -e "${RED}Response:${NC}"
  echo "$HTTP_BODY" | jq '.'
fi

echo ""

