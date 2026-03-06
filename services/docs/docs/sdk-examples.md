# SDK Examples

All examples use the base URL:

```
https://ai-gateway.portal.chalmers.se/llm/openai/v1
```

## Python — OpenAI SDK

### Basic request

```python
from openai import OpenAI

client = OpenAI(
    api_key="YOUR_API_KEY",
    base_url="https://ai-gateway.portal.chalmers.se/llm/openai/v1"
)

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Explain quantum computing in one paragraph"}]
)

print(response.choices[0].message.content)
```

### Streaming

```python
from openai import OpenAI

client = OpenAI(
    api_key="YOUR_API_KEY",
    base_url="https://ai-gateway.portal.chalmers.se/llm/openai/v1"
)

stream = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Write a short poem about code"}],
    stream=True,
    stream_options={"include_usage": True}
)

for chunk in stream:
    if chunk.choices and chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
print()
```

### Anthropic models (same SDK)

The gateway translates OpenAI format to Anthropic format automatically:

```python
# Works with the same OpenAI client — no Anthropic SDK needed
response = client.chat.completions.create(
    model="claude-haiku-4-5",  # Anthropic model via OpenAI-compatible API
    messages=[{"role": "user", "content": "Hello, Claude!"}]
)
```

## Python — Anthropic SDK

For native Anthropic SDK usage (e.g., Claude Code sidecar):

```python
import anthropic

client = anthropic.Anthropic(
    api_key="YOUR_API_KEY",
    base_url="https://ai-gateway.portal.chalmers.se/llm/anthropic"
)

message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello!"}]
)
print(message.content[0].text)
```

!!! note
    The Claude Code sidecar endpoint (`/llm/anthropic/v1`) is restricted to the `claude_code_users` consumer group.

## JavaScript / TypeScript

```typescript
import OpenAI from "openai";

const client = new OpenAI({
  apiKey: "YOUR_API_KEY",
  baseURL: "https://ai-gateway.portal.chalmers.se/llm/openai/v1",
});

const response = await client.chat.completions.create({
  model: "gpt-4o-mini",
  messages: [{ role: "user", content: "Hello from JS!" }],
});

console.log(response.choices[0].message.content);
```

## cURL

```bash
# OpenAI model
curl https://ai-gateway.portal.chalmers.se/llm/openai/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "Hello"}]}'

# Anthropic model (same endpoint, OpenAI format)
curl https://ai-gateway.portal.chalmers.se/llm/openai/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-haiku-4-5", "messages": [{"role": "user", "content": "Hello"}]}'

# Embeddings
curl https://ai-gateway.portal.chalmers.se/llm/openai/v1/embeddings \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "nomic-embed-text-v1.5", "input": "Hello world"}'
```

## Environment variables

Most SDKs and tools respect these environment variables:

```bash
export OPENAI_API_KEY="YOUR_API_KEY"
export OPENAI_BASE_URL="https://ai-gateway.portal.chalmers.se/llm/openai/v1"
```

Once set, the OpenAI SDK picks them up automatically — no need to pass `api_key` or `base_url` in code.

Get your key from the [Portal](/portal/){:target="_blank"} if you haven't already.

```python
from openai import OpenAI
client = OpenAI()  # reads from environment
```
