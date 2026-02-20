# Plugin Inventory

Overview of custom and built-in plugins used in gateway routes.

## Custom Plugins

Located at: `services/apisix/lua/apisix/plugins/`

### auth-transform
**Type**: Proper APISIX plugin (priority: 12020)
**Phase**: rewrite

**Schema**:
```json
{
  "auth-transform": {
    "mode": "bearer_to_api_key",
    "sanitize_request_ids": true
  }
}
```

**Function**:
- Converts `Authorization: Bearer <token>` to `X-Api-Key: <token>`
- Sanitizes request IDs (moves client X-Request-Id to X-User-Request-Id)
- Runs before auth plugins

**Why**: OpenAI SDKs send Bearer auth; APISIX key-auth expects X-Api-Key header.

---

### model-policy
**Type**: Proper APISIX plugin (priority: 2000)
**Phase**: access

**Schema**:
```json
{
  "model-policy": {
    "action": "enforce"  // or "render"
  }
}
```

**Function**:
- `action=enforce`: Validates model in request body against MODEL_REGISTRY, checks consumer group access
- `action=render`: Returns /models response filtered by consumer group
- Sets ctx vars: `$model_requested`, `$model_effective`, `$upstream_provider`
- Returns 400 for unknown models, 403 for forbidden models

**MODEL_REGISTRY**: Single source of truth for all models (defined in plugin).

**Why**: Tier-based model access (base_user: mini models, premium_user: all).

---

### openai-auth
**Type**: Proper APISIX plugin (priority: 2500)
**Phase**: rewrite

**Schema**:
```json
{
  "openai-auth": {
    "header": "x-api-key",
    "hide_credentials": true
  }
}
```

**Function**:
- Looks up API key against key-auth consumers
- Returns OpenAI-format error responses (401 with `error.code`)
- Attaches consumer to context

**Why**: Same as key-auth but with OpenAI-compatible error format.

---

### billing-extractor
**Type**: Proper APISIX plugin (priority: 1000)
**Phase**: access, body_filter

**Schema**:
```json
{
  "billing-extractor": {
    "provider": "openai",  // or "anthropic", "litellm"
    "endpoint": "chat"
  }
}
```

**Function**:
- Parses response body (handles SSE streaming)
- Extracts usage tokens and provider response ID
- Sets ctx vars for file-logger: `$billing_model`, `$billing_usage_json`, `$billing_provider_response_id`

**Why**: Usage tracking for billing.

---

### provider-response-id
**Type**: Proper APISIX plugin (priority: 900)
**Phase**: body_filter

**Schema**:
```json
{
  "provider-response-id": {}
}
```

**Function**:
- Extracts `id` field from response (chatcmpl-xxx, msg_xxx)
- Sets `$provider_response_id` ctx var for logging
- Handles both streaming (SSE) and non-streaming responses

**Why**: Needed for ai-proxy routes where billing-extractor isn't used.

---

### response-wiretap
**Type**: Proper APISIX plugin (priority: 900)
**Phase**: body_filter

**Schema**:
```json
{
  "response-wiretap": {
    "enabled": true,
    "max_body_bytes": 524288,
    "log_path": "/usr/local/apisix/logs/wiretap.jsonl"
  }
}
```

**Function**:
- Captures full response bodies to JSONL file
- Useful for debugging streaming issues

---

## Built-in APISIX Plugins

### key-auth
**Function**: Authenticate requests against consumer credentials.

### ai-proxy
**Function**: Route OpenAI-format requests to LLM providers (OpenAI, Anthropic).

### proxy-rewrite
**Function**: Rewrite URI and headers before forwarding to upstream.

### request-id
**Function**: Generate/propagate X-Request-Id for tracing.

### file-logger
**Function**: Write JSON log lines to file.

### cors
**Function**: Handle CORS headers and preflight requests.

---

## Route Plugin Matrix

| Plugin | /llm/ai-proxy/* | /llm/litellm/* | /llm/claude-code/* |
|--------|-----------------|----------------|-------------------|
| auth-transform | Yes | Yes | Yes |
| openai-auth | Yes | Yes | No |
| key-auth | No | No | Yes |
| model-policy | Yes | No | No |
| ai-proxy | Yes | No | No |
| proxy-rewrite | No | Yes | Yes |
| billing-extractor | No | Yes | Yes |
| provider-response-id | Yes | Yes | No |
| file-logger | Yes | Yes | Yes |
| request-id | Yes | Yes | Yes |

---

## Ctx Variables for Logging

| Variable | Source | Description |
|----------|--------|-------------|
| `$model_requested` | model-policy | Model from request body |
| `$model_effective` | model-policy | Actual model used |
| `$upstream_provider` | model-policy | openai/anthropic |
| `$provider_response_id` | provider-response-id, billing-extractor | chatcmpl-xxx or msg_xxx |
| `$billing_usage_json` | billing-extractor | JSON usage object |
| `$billing_model` | billing-extractor | Model from request |
