# LLM Gateway User Guide

API gateway providing unified access to Anthropic, OpenAI, and LiteLLM with authentication and rate limiting.

## Getting Started

### 1. Get API Key

Visit the portal: `https://lamassu.ita.chalmers.se/portal/`

Sign in with your Chalmers credentials to get your API key. You can recycle (regenerate) your key at any time—this invalidates the old key immediately.

### 2. First Request

```bash
curl https://lamassu.ita.chalmers.se/provider/anthropic/v1/messages \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Authentication

All requests require Bearer token authentication:

```
Authorization: Bearer <your-key>
```

## Available Endpoints

| Use Case | Base URL | SDK Format |
|----------|----------|------------|
| Anthropic native | `/provider/anthropic/v1` | Anthropic |
| Anthropic via OpenAI | `/provider/anthropic/openai/v1` | OpenAI |
| OpenAI | `/provider/openai/v1` | OpenAI |
| LiteLLM (any model) | `/provider/litellm` | OpenAI |
| Open WebUI (server) | `/openwebui/central/v1` | OpenAI |
| Open WebUI (browser) | `/openwebui/direct/v1` | OpenAI + CORS |

Full URLs use base `https://lamassu.ita.chalmers.se`

## Usage Examples

### Python - Anthropic SDK

```python
import anthropic

client = anthropic.Anthropic(
    api_key="<your-key>",
    base_url="https://lamassu.ita.chalmers.se/provider/anthropic/v1"
)

message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}]
)
```

### Python - OpenAI SDK

```python
from openai import OpenAI

# For OpenAI models
client = OpenAI(
    api_key="<your-key>",
    base_url="https://lamassu.ita.chalmers.se/provider/openai/v1"
)

# For Anthropic models via OpenAI SDK
client = OpenAI(
    api_key="<your-key>",
    base_url="https://lamassu.ita.chalmers.se/provider/anthropic/openai/v1"
)

response = client.chat.completions.create(
    model="claude-sonnet-4-20250514",
    messages=[{"role": "user", "content": "Hello"}]
)
```

### Coding Agents

**Claude Code:**
```bash
export ANTHROPIC_API_KEY="<your-key>"
export ANTHROPIC_BASE_URL="https://lamassu.ita.chalmers.se/provider/anthropic/v1"
```

**OpenCode / Cursor / Other OpenAI-compatible agents:**
```bash
export OPENAI_API_KEY="<your-key>"
export OPENAI_BASE_URL="https://lamassu.ita.chalmers.se/provider/anthropic/openai/v1"
```

### Open WebUI

In Settings → Connections → OpenAI API:

- **API Base URL:** `https://lamassu.ita.chalmers.se/openwebui/central/v1`
- **API Key:** `<your-key>`

### Mathematica

```mathematica
ServiceConnect["OpenAI",
  "APIKey" -> "<your-key>",
  "Endpoint" -> "https://lamassu.ita.chalmers.se/provider/openai/v1"
]
```

### curl

```bash
# Anthropic format
curl https://lamassu.ita.chalmers.se/provider/anthropic/v1/messages \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-sonnet-4-20250514", "max_tokens": 100, "messages": [{"role": "user", "content": "Hello"}]}'

# OpenAI format
curl https://lamassu.ita.chalmers.se/provider/openai/v1/chat/completions \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Rate Limits

| Tier | Requests/Week |
|------|---------------|
| Base | 10,000 |
| Premium | 50,000 |

Monitor usage via response headers:
- `X-RateLimit-Limit` - your quota
- `X-RateLimit-Remaining` - requests left
- `X-RateLimit-Reset` - reset timestamp

## Streaming

Streaming works for all endpoints. For OpenAI SDK with usage tracking in streams:

```python
response = client.chat.completions.create(
    model="gpt-4o",
    messages=[...],
    stream=True,
    stream_options={"include_usage": True}
)
```

## Errors

| Code | Meaning |
|------|---------|
| 401 | Invalid or missing API key |
| 429 | Rate limit exceeded |
| 502 | Upstream provider error |

## FAQ

**Q: Can I use the same key for multiple providers?**
A: Yes, one key works for all endpoints.

**Q: How do I check my current usage?**
A: Check `X-RateLimit-Remaining` header in any response.

**Q: My key stopped working**
A: You may have recycled it in the portal. Get your new key from the portal.

**Q: Which models are available?**
A: Depends on the endpoint. Use `/models` endpoint to list available models (e.g., `/provider/openai/v1/models`).
