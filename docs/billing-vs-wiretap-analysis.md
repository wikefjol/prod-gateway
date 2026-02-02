# Billing vs Wiretap Log Analysis Report

**Date:** 2026-02-02
**Analyst:** Claude
**Purpose:** Identify discrepancies between billing-extractor and raw wiretap data to inform billing logic fixes

---

## Executive Summary

The billing-extractor plugin has **two critical issues**:

1. **Gzip-encoded responses are not parsed** - Non-streaming responses from OpenAI and Anthropic-via-OpenAI endpoints return `Content-Encoding: gzip`, which billing-extractor cannot decode
2. **OpenAI Responses API uses different event structure** - The Responses API sends `event: response.completed` with nested `response.usage`, not top-level `usage`

---

## Data Collection Summary

| Route | Billing Entries | Wiretap Entries |
|-------|----------------|-----------------|
| anthropic-messages | 5 | 1 |
| anthropic-openai | 36 | 15 |
| openai-chat | 52 | 23 |
| openai-responses | 21 | 13 |

---

## Route-by-Route Analysis

### 1. Anthropic Messages (`/provider/anthropic/v1/messages`)

**Status: Working correctly**

| Metric | Billing | Wiretap |
|--------|---------|---------|
| Provider | `anthropic` | `anthropic` |
| Response ID | `msg_0121659zCydU9fPPPjtBJmNU` | `msg_0121659zCydU9fPPPjtBJmNU` |
| Input tokens | 11 | 11 |
| Output tokens | 5 | 5 |

**Sample billing entry:**
```json
{
  "model": "claude-3-haiku-20240307",
  "provider_response_id": "msg_0121659zCydU9fPPPjtBJmNU",
  "usage": "{\"input_tokens\":11,\"output_tokens\":5,\"cache_creation_input_tokens\":0,...}",
  "usage_present": "true",
  "is_streaming": "false"
}
```

**Sample wiretap raw response:**
```json
{
  "id": "msg_0121659zCydU9fPPPjtBJmNU",
  "model": "claude-3-haiku-20240307",
  "usage": {
    "input_tokens": 11,
    "output_tokens": 5,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 0
  }
}
```

**Verdict:** ✅ Usage extraction matches exactly

---

### 2. OpenAI Chat Completions (`/provider/openai/v1/chat/completions`)

**Status: Partial failure**

#### Streaming requests: ✅ Working

| Condition | Count | usage_present |
|-----------|-------|---------------|
| status=200, streaming=true | 3 | `true` |

**Last SSE frame contains usage:**
```
data: {"id":"chatcmpl-D4n9o6z7Vgcg9K8IE1cqCm6MzMdTR",...,"usage":{"prompt_tokens":14,"completion_tokens":2,"total_tokens":16,...}}
```

#### Non-streaming requests: ❌ FAILING

| Condition | Count | usage_present |
|-----------|-------|---------------|
| status=200, streaming=false | 13 | `false` |

**Root cause:** Response body is gzip-compressed

**Wiretap evidence:**
```json
{
  "content_encoding": "gzip",
  "is_base64": true,
  "raw_chunks": ["H4sIAAAAAAAA..."] // base64-encoded gzip data
}
```

**Billing entry shows failure:**
```json
{
  "status": 200,
  "is_streaming": "false",
  "usage_present": "false",
  "usage": ""
}
```

**Verdict:** ❌ Billing extractor cannot decompress gzip responses

---

### 3. Anthropic via OpenAI-Compatible (`/provider/anthropic/v1/chat/completions`)

**Status: Partial failure (same gzip issue)**

| Condition | Count | usage_present |
|-----------|-------|---------------|
| status=200, streaming=true | 2 | `true` |
| status=200, streaming=false | 3 | `false` |

#### Streaming: ✅ Working

**SSE frame with usage:**
```
data: {"id":"msg_01HfraiweyYsQqZh3UiZkrHr","choices":[...],"usage":{"completion_tokens":12,"prompt_tokens":14,"total_tokens":26}}
```

#### Non-streaming: ❌ FAILING (gzip)

Same root cause as OpenAI Chat - responses are gzip-encoded.

---

### 4. OpenAI Responses API (`/provider/openai/v1/responses`)

**Status: Failing (multiple issues)**

| Condition | Count | usage_present |
|-----------|-------|---------------|
| status=200, streaming=true | 2 | `false` |
| status=200, streaming=false | 2 | `false` |

#### Issue 1: Different event structure for streaming

The Responses API uses a different SSE event format:

```
event: response.completed
data: {"type":"response.completed","response":{...,"usage":{...}}}
```

**Key differences:**
- Event type is `response.completed`, not just `data:`
- Usage is nested at `response.usage`, not top-level `usage`
- Response ID format is `resp_...`, not `chatcmpl-...`

**Billing extractor only looks for:**
```lua
if data.usage then  -- Won't find nested response.usage
    ctx.billing_usage_json = cjson.encode(data.usage)
end
```

#### Issue 2: Gzip encoding for non-streaming

Same as other routes - non-streaming responses are gzip-compressed.

**Wiretap evidence of Responses API structure:**
```json
{
  "type": "response.completed",
  "response": {
    "id": "resp_057b67ae5fe03af901698096309c5481...",
    "model": "gpt-3.5-turbo-0125",
    "usage": {
      "input_tokens": 17,
      "output_tokens": 41,
      "total_tokens": 58,
      "input_tokens_details": {"cached_tokens": 0},
      "output_tokens_details": {"reasoning_tokens": 0}
    }
  }
}
```

---

## Issue Summary

### Issue 1: Gzip-encoded responses not handled

**Affected routes:**
- `/provider/openai/v1/chat/completions` (non-streaming)
- `/provider/anthropic/v1/chat/completions` (non-streaming)
- `/provider/openai/v1/responses` (non-streaming)

**Impact:** All non-streaming 200 responses have `usage_present: false`

**Current code (billing-extractor.lua:199-203):**
```lua
local raw = table.concat(ctx._billing_resp_chunks)
local resp = cjson.decode(raw)  -- Fails on gzip binary data
if not resp then
    ctx.billing_usage_present = "false"
    return
end
```

**Fix options:**
1. Decompress gzip in Lua (requires zlib/lua-zlib)
2. Request uncompressed responses via `Accept-Encoding: identity` header
3. Use APISIX's built-in decompression if available

### Issue 2: OpenAI Responses API event structure

**Affected route:** `/provider/openai/v1/responses` (streaming)

**Impact:** Streaming 200 responses have `usage_present: false`

**Current code looks for top-level usage:**
```lua
if data.usage then
    ctx.billing_usage_json = cjson.encode(data.usage)
end
```

**Actual structure:**
```json
{"type":"response.completed","response":{"usage":{...}}}
```

**Fix required:**
```lua
-- Check for nested response.usage (Responses API)
if data.response and data.response.usage then
    ctx.billing_usage_json = cjson.encode(data.response.usage)
    ctx._billing_usage_found = true
end
```

### Issue 3: Response ID extraction for Responses API

**Current code:**
```lua
if data.id and data.id ~= "" then
    ctx.billing_provider_response_id = data.id
end
```

**Actual structure:**
```json
{"response":{"id":"resp_..."}}
```

**Fix required:**
```lua
if data.response and data.response.id then
    ctx.billing_provider_response_id = data.response.id
end
```

---

## Accuracy Statistics

| Route | Streaming Accuracy | Non-streaming Accuracy |
|-------|-------------------|------------------------|
| anthropic-messages | N/A (not tested) | 100% |
| anthropic-openai | 100% (2/2) | 0% (0/3) |
| openai-chat | 100% (3/3) | 0% (0/13) |
| openai-responses | 0% (0/2) | 0% (0/2) |

**Overall:** ~23% of 200 responses have correct usage extraction

---

## Recommended Fixes (Priority Order)

1. **HIGH: Add gzip decompression** - Fixes non-streaming for all routes
2. **HIGH: Handle Responses API nested structure** - Fixes streaming for Responses API
3. **MEDIUM: Add Accept-Encoding: identity to proxy-rewrite** - Alternative to decompression
4. **LOW: Add response ID extraction for nested format**

---

## Appendix: Log Locations

- Billing: `/var/log/apisix/billing/<route-name>.log`
- Wiretap: `/var/log/apisix/wiretap/<route-name>.jsonl`

## Appendix: Content-Encoding by Response Type

| Response Type | Content-Encoding | Billing Extractor Status |
|---------------|------------------|-------------------------|
| Streaming SSE | `identity` (chunked) | ✅ Works |
| Non-streaming JSON | `gzip` | ❌ Fails |
