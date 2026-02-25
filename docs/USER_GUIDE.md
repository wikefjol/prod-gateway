# LLM Gateway User Guide

API gateway providing unified access to Anthropic and OpenAI with authentication and rate limiting.

## Getting Started

### 1. Get API Key

Visit the portal: `https://lamassu.ita.chalmers.se/portal/`

Sign in with your Chalmers credentials to get your API key. You can recycle (regenerate) your key at any time—this invalidates the old key immediately.

### 2. First Request

```bash
curl https://lamassu.ita.chalmers.se/llm/ai-proxy/v1/chat/completions \
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

| Use Case | Base URL | SDK Format |
|----------|----------|------------|
| ai-proxy (all models) | `/llm/ai-proxy/v1` | OpenAI |
| Claude Code sidecar | `/llm/claude-code/v1` | Anthropic |

Full URLs use base `https://lamassu.ita.chalmers.se`

## Usage Examples

### Python - OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    api_key="<your-key>",
    base_url="https://lamassu.ita.chalmers.se/llm/ai-proxy/v1"
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
export ANTHROPIC_BASE_URL="https://lamassu.ita.chalmers.se/llm/claude-code/v1"
```

**OpenCode / Cursor / Other OpenAI-compatible agents:**
```bash
export OPENAI_API_KEY="<your-key>"
export OPENAI_BASE_URL="https://lamassu.ita.chalmers.se/llm/ai-proxy/v1"
```

### Mathematica

```mathematica
ServiceConnect["OpenAI",
  "APIKey" -> "<your-key>",
  "Endpoint" -> "https://lamassu.ita.chalmers.se/llm/ai-proxy/v1"
]
```

### curl

```bash
# OpenAI model
curl https://lamassu.ita.chalmers.se/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "Hello"}]}'

# Anthropic model (same endpoint, OpenAI format)
curl https://lamassu.ita.chalmers.se/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-haiku-4-5", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Rate Limits

| Tier | Requests/Week |
|------|---------------|
| Base | 1,000,000 |
| Premium | 1,000,000 |

Monitor usage via response headers:
- `X-RateLimit-Limit` - your quota
- `X-RateLimit-Remaining` - requests left
- `X-RateLimit-Reset` - reset timestamp

## Streaming

Streaming works for all endpoints. For OpenAI SDK with usage tracking in streams:

```python
response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[...],
    stream=True,
    stream_options={"include_usage": True}
)
```

## Errors

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
A: Use the `/llm/ai-proxy/v1/models` endpoint to list available models for your tier.
