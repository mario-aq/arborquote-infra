
## 📋 Plan: Quote Text Polishing/Translation for PDF Generation

### **Changes from Original Plan**

| Item | Original | Revised |
|------|----------|---------|
| Timeout | 60s | **120s** |
| GPT failure | Graceful degradation | **Return 500 error** |
| PII handling | Not specified | **Strip ALL PII before sending to GPT** |

---

### **PII Protection (Critical)**

**What we send to GPT (text fields only):**
```json
{
  "notes": "cliente quiere trabajo urgente",
  "items": [
    { "itemId": "01ABC...", "description": "arbol grande de roble" }
  ]
}
```

**What we do NOT send to GPT:**
- ❌ `customerName`, `customerPhone`, `customerEmail`, `customerAddress`
- ❌ `userId`, `quoteId`
- ❌ Provider/company info
- ❌ Prices, dates, timestamps
- ❌ Photos, PDF metadata, status

This mirrors the voice feature's `sanitize_quote_for_gpt` approach.

---

### **Implementation Flow**

```
1. Fetch quote from DynamoDB
2. Compute hash
3. Check cache → if cached, return existing PDF
4. Extract ONLY text fields (notes, item descriptions) ← Sanitize
5. Send sanitized text to GPT for polish/translate
6. If GPT fails → return 500 error ← No fallback
7. Merge polished text back into quote copy
8. Generate PDF with polished quote
9. Upload to S3
10. Update DynamoDB metadata (original hash only)
11. Return URL
```

---

### **Files to Modify**

| File | Change |
|------|--------|
| `lambda/shared/openai_client.rb` | Add `polish_text_for_pdf(notes, items_text, locale)` method |
| `lambda/generate_pdf/handler.rb` | Extract text → call GPT → merge back → generate PDF |
| `lib/arborquote-backend-stack.ts` | Add OPENAI env vars, timeout 120s |

---

### **GPT Payload Structure**

**Request to GPT:**
```json
{
  "notes": "cliente quiere trabajo urgente",
  "items": [
    { "index": 0, "description": "arbol grande de roble" },
    { "index": 1, "description": "stump grinding needed" }
  ]
}
```

**Response from GPT:**
```json
{
  "notes": "El cliente desea el trabajo con urgencia.",
  "items": [
    { "index": 0, "description": "Árbol grande de roble" },
    { "index": 1, "description": "Molienda de tocón necesaria" }
  ]
}
```

Note: Using `index` instead of `itemId` to avoid sending any identifiers to GPT.

---

### **GPT System Prompt (Revised)**

```text
You are a professional document editor for a tree service quoting system.

Your task: Polish and translate text fields to ensure they are professional, 
grammatically correct, and in the target language.

Target language: {locale}
- "en" → Professional English
- "es" → Professional Spanish

Input: JSON with notes and item descriptions
Output: Same structure with polished text

Rules:
1. Translate any text NOT in the target language
2. Fix grammar, spelling, punctuation, capitalization
3. Make text professional but preserve original meaning
4. Keep it concise - don't add unnecessary words
5. If text is already correct, return it unchanged

Return ONLY valid JSON matching the input structure.
```

---

### **Error Handling**

| Scenario | Response |
|----------|----------|
| GPT call succeeds | Continue with PDF generation |
| GPT call fails (timeout, rate limit, API error) | **Return 500 error** |
| GPT returns invalid JSON | **Return 500 error** |
| Quote has no text to polish (empty notes, empty items) | Skip GPT, continue with PDF |

---

### **CDK Changes**

```typescript
const generatePdfFunction = new lambda.Function(this, 'GeneratePdfFunction', {
  // ... existing config
  memorySize: 512,
  timeout: cdk.Duration.seconds(120),  // ← Increased from 60s
  environment: {
    ...commonLambdaProps.environment,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY || '',
    OPENAI_GPT_MODEL: process.env.OPENAI_GPT_MODEL || 'gpt-4o-mini',
  },
});
```

---

### **Implementation Steps**

1. **Update CDK stack**
   - Add OPENAI env vars to GeneratePDF Lambda
   - Set timeout to 120s

2. **Add `polish_text_for_pdf` to `openai_client.rb`**
   - Accept: `notes` (string), `items_text` (array of {index, description}), `locale`
   - Send minimal payload to GPT (no PII)
   - Return polished text or raise error

3. **Update `generate_pdf/handler.rb`**
   - After cache check fails:
     - Extract `notes` and `items[].description` (no IDs, no PII)
     - Call `polish_text_for_pdf`
     - If error → return 500
     - Create copy of quote with polished text
     - Generate PDF with polished copy

4. **Test**
   - Generate PDF with mixed-language text
   - Verify polished in PDF, original in DynamoDB
   - Test GPT failure → 500 response

---

### **Example Code Flow**

```ruby
# In generate_pdf/handler.rb, after cache check fails:

# 1. Extract text fields ONLY (no PII)
text_to_polish = {
  notes: quote['notes'] || '',
  items: (quote['items'] || []).map.with_index do |item, idx|
    { index: idx, description: item['description'] || '' }
  end
}

# 2. Skip if nothing to polish
unless text_to_polish[:notes].empty? && text_to_polish[:items].all? { |i| i[:description].empty? }
  # 3. Call GPT (may raise error → 500)
  polished = OpenAiClient.polish_text_for_pdf(
    notes: text_to_polish[:notes],
    items_text: text_to_polish[:items],
    locale: locale
  )
  
  # 4. Create polished quote copy (deep clone)
  polished_quote = quote.dup
  polished_quote['notes'] = polished[:notes]
  polished_quote['items'] = quote['items'].map.with_index do |item, idx|
    item.merge('description' => polished[:items][idx][:description])
  end
end

# 5. Generate PDF with polished quote
pdf_data = PdfGenerator.generate_pdf(polished_quote || quote, user, company, locale)
```

---

### **Summary of Key Points**

| Aspect | Decision |
|--------|----------|
| Timeout | 120 seconds |
| GPT failure | Return 500 (no fallback) |
| PII to GPT | **None** - only notes and descriptions |
| Cache behavior | Polish happens AFTER cache check |
| Storage | Never persist polished text |

---

**Ready to implement?** 🚀