# LLM Gateway API Reference

API gateway for LLM providers. All endpoints under `/llm/*`.

## Authentication

All endpoints require Bearer token authentication:

```
Authorization: Bearer <consumer-api-key>
```

Consumers created via portal (OIDC/EntraID). Keys managed in portal UI.

## Setups

Three parallel setups available:

| Setup | Base Path | Protocol | Routing |
|-------|-----------|----------|---------|
| LiteLLM | `/llm/litellm/v1` | OpenAI-compatible | External LiteLLM server |
| ai-proxy | `/llm/ai-proxy/v1` | OpenAI-compatible | APISIX-native, model-based |
| Claude Code | `/llm/claude-code/v1` | Anthropic native | Direct to Anthropic |

---

## Setup A: LiteLLM

External LiteLLM server handles model routing.

### POST /llm/litellm/v1/chat/completions

OpenAI chat completions format. Supports streaming.

```bash
curl -X POST https://gateway/llm/litellm/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": false
  }'
```

### GET /llm/litellm/v1/models

List available models (from LiteLLM).

```bash
curl https://gateway/llm/litellm/v1/models \
  -H "Authorization: Bearer $API_KEY"
```

---

## Setup B: ai-proxy (APISIX Native)

APISIX routes to provider based on model name prefix:
- `gpt-*`, `o1-*`, `o3-*`, `davinci-*`, `text-embedding-*` → OpenAI
- `claude-*` → Anthropic

### POST /llm/ai-proxy/v1/chat/completions

OpenAI chat completions format. Supports streaming.

```bash
# OpenAI model
curl -X POST https://gateway/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello"}]
  }'

# Anthropic model (same endpoint, OpenAI format)
curl -X POST https://gateway/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-haiku-20240307",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### GET /llm/ai-proxy/v1/models

List models allowed for consumer's group.

```bash
curl https://gateway/llm/ai-proxy/v1/models \
  -H "Authorization: Bearer $API_KEY"
```

Response (OpenAI format):
```json
{
  "object": "list",
  "data": [
    {"id": "gpt-4o-mini", "object": "model", "created": 1721172741, "owned_by": "system"},
    {"id": "claude-3-haiku-20240307", "object": "model", "created": 1709769600, "owned_by": "anthropic"}
  ]
}
```

---

## Setup C: Claude Code Sidecar

Native Anthropic Messages API. **Restricted to `claude_code_users` group.**

### POST /llm/claude-code/v1/messages

Anthropic Messages API format.

```bash
curl -X POST https://gateway/llm/claude-code/v1/messages \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### POST /llm/claude-code/v1/messages/count_tokens

Token counting endpoint.

```bash
curl -X POST https://gateway/llm/claude-code/v1/messages/count_tokens \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

---

## Consumer Groups & Model Access

| Group | Models | Rate Limit |
|-------|--------|------------|
| `base_user` | gpt-4o-mini, gpt-3.5-turbo-0125, claude-3-5-haiku-20241022, claude-3-haiku-20240307 | 10k/week |
| `premium_user` | All models | 10k/week |
| `claude_code_users` | All models + Claude Code sidecar access | 10k/week |

## Available Models

### OpenAI
- gpt-4o, gpt-4o-mini
- gpt-4-turbo, gpt-4
- gpt-3.5-turbo-0125
- o1, o1-mini, o1-preview
- o3-mini

### Anthropic
- claude-sonnet-4-20250514, claude-opus-4-20250514
- claude-3-5-sonnet-20241022, claude-3-5-haiku-20241022
- claude-3-opus-20240229, claude-3-sonnet-20240229, claude-3-haiku-20240307

---

## Common Headers

**Request:**
- `Authorization: Bearer <key>` (required)
- `Content-Type: application/json` (for POST)
- `X-Request-Id: <uuid>` (optional, generated if missing)

**Response:**
- `X-Request-Id` - Request trace ID
- `X-RateLimit-Limit` - Quota limit
- `X-RateLimit-Remaining` - Remaining requests
- `X-RateLimit-Reset` - Reset timestamp

## Error Responses

```json
{"error": {"message": "...", "type": "...", "code": "..."}}
```

| Code | Meaning |
|------|---------|
| 401 | Invalid/missing API key |
| 403 | Model not allowed for consumer group |
| 429 | Rate limit exceeded |
| 502 | Upstream provider error |

---

## OpenWebUI Configuration

For browser-based clients (CORS enabled on chat/models routes):

| Setup | Base URL |
|-------|----------|
| LiteLLM | `https://gateway/llm/litellm/v1` |
| ai-proxy | `https://gateway/llm/ai-proxy/v1` |
