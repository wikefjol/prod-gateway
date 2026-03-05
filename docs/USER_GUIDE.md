# LLM Gateway User Guide

API gateway providing unified access to Anthropic, OpenAI, and Alvis vLLM (C3SE HPC) with authentication and rate limiting.

## Getting Started

### 1. Get API Key

Visit the portal: `https://lamassu.ita.chalmers.se/portal/`

Sign in with your Chalmers credentials to get your API key. You can recycle (regenerate) your key at any time—this invalidates the old key immediately.

### 2. First Request

```bash
curl https://lamassu.ita.chalmers.se/llm/openai/v1/chat/completions \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Authentication

All requests require Bearer token authentication:

```
Authorization: Bearer <your-key>
```

## Available Endpoints

| Use Case | Base URL | Protocol |
|----------|----------|----------|
| Chat completions (all models) | `/llm/openai/v1` | OpenAI-compatible |
| Embeddings | `/llm/openai/v1` | OpenAI-compatible |
| Anthropic native (Claude Code) | `/llm/anthropic/v1` | Anthropic native |

Full URLs use base `https://lamassu.ita.chalmers.se`.

**Anthropic native endpoint** is restricted to the `claude_code_users` consumer group.

## Consumer Groups & Model Access

| Group | Models | Rate Limit |
|-------|--------|------------|
| `base_user` | gpt-4o-mini, gpt-3.5-turbo-0125, claude-haiku-4-5, qwen3-coder-30b, gemma-3-12b-it, gpt-oss-20b, nomic-embed-text-v1.5 | 1M req/week |
| `premium_user` | All models | 1M req/week |
| `claude_code_users` | All models + Claude Code sidecar | 1M req/week |

For the current model list, query the API: `GET /llm/openai/v1/models`

## Usage Examples

### Python - OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    api_key="<your-key>",
    base_url="https://lamassu.ita.chalmers.se/llm/openai/v1"
)

# Works with both OpenAI and Anthropic models
response = client.chat.completions.create(
    model="gpt-4o-mini",  # or "claude-haiku-4-5"
    messages=[{"role": "user", "content": "Hello"}]
)
```

### Coding Agents

**Claude Code:**
```bash
export ANTHROPIC_API_KEY="<your-key>"
export ANTHROPIC_BASE_URL="https://lamassu.ita.chalmers.se/llm/anthropic/v1"
```

**OpenCode / Cursor / Other OpenAI-compatible agents:**
```bash
export OPENAI_API_KEY="<your-key>"
export OPENAI_BASE_URL="https://lamassu.ita.chalmers.se/llm/openai/v1"
```

### OpenWebUI

Browser-based clients (CORS enabled on chat/models routes):

| Setup | Base URL |
|-------|----------|
| OpenAI protocol | `https://lamassu.ita.chalmers.se/llm/openai/v1` |

### Mathematica

```mathematica
ServiceConnect["OpenAI",
  "APIKey" -> "<your-key>",
  "Endpoint" -> "https://lamassu.ita.chalmers.se/llm/openai/v1"
]
```

### curl

```bash
# OpenAI model
curl https://lamassu.ita.chalmers.se/llm/openai/v1/chat/completions \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "Hello"}]}'

# Anthropic model (same endpoint, OpenAI format)
curl https://lamassu.ita.chalmers.se/llm/openai/v1/chat/completions \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-haiku-4-5", "messages": [{"role": "user", "content": "Hello"}]}'

# Alvis vLLM model (same endpoint)
curl https://lamassu.ita.chalmers.se/llm/openai/v1/chat/completions \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3-coder-30b", "messages": [{"role": "user", "content": "Hello"}]}'

# Embeddings
curl https://lamassu.ita.chalmers.se/llm/openai/v1/embeddings \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "nomic-embed-text-v1.5", "input": "Hello world"}'
```

## Common Headers

**Request:**
- `Authorization: Bearer <key>` (required)
- `Content-Type: application/json` (for POST)
- `X-Request-Id: <uuid>` (optional, generated if missing)

**Response:**
- `X-Request-Id` — request trace ID
- `X-RateLimit-Limit` — quota limit
- `X-RateLimit-Remaining` — remaining requests
- `X-RateLimit-Reset` — reset timestamp

## Rate Limits

| Tier | Requests/Week |
|------|---------------|
| Base | 1,000,000 |
| Premium | 1,000,000 |

## Streaming

Streaming works for all endpoints. For usage tracking in streams:

```python
response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[...],
    stream=True,
    stream_options={"include_usage": True}
)
```

## Errors

```json
{"error": {"message": "...", "type": "...", "code": "..."}}
```

| Code | Meaning |
|------|---------|
| 401 | Invalid or missing API key |
| 403 | Model not allowed for your tier |
| 429 | Rate limit exceeded |
| 502 | Upstream provider error |

## FAQ

**Q: Can I use the same key for multiple providers?**
A: Yes, one key works for all endpoints. Model routing is automatic based on model name.

**Q: How do I check my current usage?**
A: Check `X-RateLimit-Remaining` header in any response.

**Q: My key stopped working**
A: You may have recycled it in the portal. Get your new key from the portal.

**Q: Which models are available?**
A: Use the `/llm/openai/v1/models` endpoint to list available models for your tier.
