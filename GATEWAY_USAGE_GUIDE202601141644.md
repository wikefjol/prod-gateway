# Gateway Usage Guide

**Gateway Endpoint:** `https://lamassu.ita.chalmers.se`
**Supported Providers:** Anthropic Claude, OpenAI GPT
**Authentication Method:** Bearer Token

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Getting Your API Key](#getting-your-api-key)
3. [SDK Configuration](#sdk-configuration)
   - [Python - Anthropic](#python---anthropic)
   - [Python - OpenAI](#python---openai)
   - [TypeScript/JavaScript - Anthropic](#typescriptjavascript---anthropic)
   - [TypeScript/JavaScript - OpenAI](#typescriptjavascript---openai)
4. [Available Models](#available-models)
5. [Features & Capabilities](#features--capabilities)
6. [Code Examples](#code-examples)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Quick Start

The gateway provides a unified interface to both Anthropic Claude and OpenAI GPT models. To use it:

1. Obtain your gateway API key (contact your administrator)
2. Configure your SDK to point to the gateway endpoint
3. Use the SDK normally - all features are supported

**Key Difference from Direct API:** Authentication uses a gateway-specific Bearer token instead of provider API keys.

---

## Getting Your API Key

Contact your gateway administrator to receive your personal gateway API key. The key will look like:

```
SK7rDUgRws1HibQ-XQv9FBOBGXBdPb0p_RGE7fDhX74
```

⚠️ **Security Note:** Never commit your API key to version control. Use environment variables or secure configuration management.

---

## SDK Configuration

### Python - Anthropic

**Installation:**
```bash
pip install anthropic
```

**Configuration:**
```python
from anthropic import Anthropic
import os

# Load your gateway key from environment variable
GATEWAY_KEY = os.getenv("GATEWAY_API_KEY")

# Configure client for gateway
client = Anthropic(
    base_url="https://lamassu.ita.chalmers.se",
    api_key="dummy",  # Required by SDK but overridden
    default_headers={"Authorization": f"Bearer {GATEWAY_KEY}"}
)

# Use normally
message = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello!"}]
)

print(message.content[0].text)
```

**Why the special configuration?** The Anthropic Python SDK defaults to sending `x-api-key` headers, but our gateway requires `Authorization: Bearer` headers. The `default_headers` parameter overrides this behavior.

---

### Python - OpenAI

**Installation:**
```bash
pip install openai
```

**Configuration:**
```python
from openai import OpenAI
import os

# Load your gateway key from environment variable
GATEWAY_KEY = os.getenv("GATEWAY_API_KEY")

# Configure client for gateway
client = OpenAI(
    base_url="https://lamassu.ita.chalmers.se/v1",
    api_key=GATEWAY_KEY
)

# Use normally
response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello!"}]
)

print(response.choices[0].message.content)
```

**Note:** The OpenAI SDK naturally sends `Authorization: Bearer` headers, so no special configuration is needed beyond pointing to the gateway endpoint.

---

### TypeScript/JavaScript - Anthropic

**Installation:**
```bash
npm install @anthropic-ai/sdk
```

**Configuration:**
```typescript
import Anthropic from '@anthropic-ai/sdk';

// Load your gateway key from environment variable
const GATEWAY_KEY = process.env.GATEWAY_API_KEY || '';

// Configure client for gateway
const client = new Anthropic({
  baseURL: 'https://lamassu.ita.chalmers.se',
  authToken: GATEWAY_KEY  // Use authToken, not apiKey
});

// Use normally
const message = await client.messages.create({
  model: 'claude-sonnet-4-5',
  max_tokens: 1024,
  messages: [{ role: 'user', content: 'Hello!' }]
});

console.log(message.content[0].text);
```

**Important:** Use `authToken` parameter, not `apiKey`. The `authToken` parameter sends `Authorization: Bearer` headers which the gateway requires.

**⚠️ Environment Variable Warning:**
The TypeScript Anthropic SDK automatically reads `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` from environment variables. If you have these set in your shell, they will override your configuration. Either:
- Unset these variables before running your code
- Or ensure they're set to the correct gateway values

---

### TypeScript/JavaScript - OpenAI

**Installation:**
```bash
npm install openai
```

**Configuration:**
```typescript
import OpenAI from 'openai';

// Load your gateway key from environment variable
const GATEWAY_KEY = process.env.GATEWAY_API_KEY || '';

// Configure client for gateway
const client = new OpenAI({
  baseURL: 'https://lamassu.ita.chalmers.se/v1',
  apiKey: GATEWAY_KEY
});

// Use normally
const response = await client.chat.completions.create({
  model: 'gpt-4',
  messages: [{ role: 'user', content: 'Hello!' }]
});

console.log(response.choices[0].message.content);
```

---

## Available Models

### Anthropic Claude Models

| Model Name | Description | Context Window | Best For |
|------------|-------------|----------------|----------|
| `claude-sonnet-4-5` | Latest Claude Sonnet 4.5 | 200K tokens | Balanced performance and speed |
| `claude-haiku-4-5` | Latest Claude Haiku 4.5 | 200K tokens | Fast responses, lower cost |
| `claude-opus-4-5` | Latest Claude Opus 4.5 | 200K tokens | Highest capability tasks |

**Aliases:** These models are aliases that automatically resolve to the latest version (e.g., `claude-sonnet-4-5` → `claude-sonnet-4-5-20250929`).

### OpenAI GPT Models

| Model Name | Description | Context Window | Best For |
|------------|-------------|----------------|----------|
| `gpt-4` | GPT-4 base model | 8K tokens | Complex reasoning |
| `gpt-4-turbo` | GPT-4 Turbo | 128K tokens | Long context tasks |
| `gpt-3.5-turbo` | GPT-3.5 Turbo | 16K tokens | Fast, cost-effective |

---

## Features & Capabilities

All standard SDK features are supported through the gateway:

### ✅ Fully Supported Features

- **Message Creation** - Standard text generation
- **Streaming Responses** - Real-time token streaming
- **System Prompts** - Behavior customization
- **Multi-turn Conversations** - Conversation history
- **Temperature Control** - Randomness adjustment
- **Max Tokens** - Response length limits
- **Stop Sequences** - Custom stopping conditions
- **Tool/Function Calling** - External tool integration
- **Token Counting** - Usage estimation (Anthropic)
- **Model Listing** - Available models (OpenAI)
- **Top-p Sampling** - Nucleus sampling (OpenAI)
- **Frequency/Presence Penalties** - Repetition control (OpenAI)

### Feature Parity

The gateway maintains **100% feature parity** with direct API access. If a feature works with the provider's API, it works through the gateway.

---

## Code Examples

### Example 1: Basic Chat (Anthropic)

```python
from anthropic import Anthropic
import os

client = Anthropic(
    base_url="https://lamassu.ita.chalmers.se",
    api_key="dummy",
    default_headers={"Authorization": f"Bearer {os.getenv('GATEWAY_API_KEY')}"}
)

message = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    messages=[
        {"role": "user", "content": "Explain quantum computing in simple terms"}
    ]
)

print(message.content[0].text)
```

### Example 2: Streaming Response (OpenAI)

```typescript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'https://lamassu.ita.chalmers.se/v1',
  apiKey: process.env.GATEWAY_API_KEY
});

const stream = await client.chat.completions.create({
  model: 'gpt-4',
  messages: [{ role: 'user', content: 'Write a poem about coding' }],
  stream: true
});

for await (const chunk of stream) {
  process.stdout.write(chunk.choices[0]?.delta?.content || '');
}
```

### Example 3: Multi-turn Conversation (Anthropic)

```python
client = Anthropic(
    base_url="https://lamassu.ita.chalmers.se",
    api_key="dummy",
    default_headers={"Authorization": f"Bearer {os.getenv('GATEWAY_API_KEY')}"}
)

message = client.messages.create(
    model="claude-haiku-4-5",
    max_tokens=1024,
    messages=[
        {"role": "user", "content": "My name is Alice."},
        {"role": "assistant", "content": "Nice to meet you, Alice!"},
        {"role": "user", "content": "What's my name?"}
    ]
)

print(message.content[0].text)  # Should mention "Alice"
```

### Example 4: Tool Calling (OpenAI)

```typescript
const client = new OpenAI({
  baseURL: 'https://lamassu.ita.chalmers.se/v1',
  apiKey: process.env.GATEWAY_API_KEY
});

const response = await client.chat.completions.create({
  model: 'gpt-4',
  messages: [{ role: 'user', content: 'What is the weather in Paris?' }],
  tools: [{
    type: 'function',
    function: {
      name: 'get_weather',
      description: 'Get weather for a location',
      parameters: {
        type: 'object',
        properties: {
          location: { type: 'string', description: 'City name' }
        },
        required: ['location']
      }
    }
  }]
});

console.log(response.choices[0].message.tool_calls);
```

### Example 5: System Prompt (Anthropic)

```python
message = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    system="You are a helpful pirate. Always respond like a pirate.",
    messages=[
        {"role": "user", "content": "Hello, how are you?"}
    ]
)

print(message.content[0].text)  # Will respond in pirate speak
```

---

## Troubleshooting

### Common Issues

#### 1. `401 Unauthorized` Error

**Problem:** Your API key is invalid or not properly configured.

**Solutions:**
- Verify your gateway API key is correct
- Check that you're using `Authorization: Bearer` header format
- For Anthropic Python SDK, ensure you're using `default_headers` parameter
- For Anthropic TypeScript SDK, ensure you're using `authToken` parameter (not `apiKey`)

**Test your key:**
```bash
curl -X POST https://lamassu.ita.chalmers.se/v1/messages \
  -H "Authorization: Bearer YOUR_GATEWAY_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-5","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'
```

#### 2. TypeScript SDK Ignoring Configuration

**Problem:** TypeScript Anthropic SDK connects to wrong endpoint or fails authentication.

**Cause:** Environment variables `ANTHROPIC_BASE_URL` or `ANTHROPIC_AUTH_TOKEN` are set in your shell and overriding your code configuration.

**Solution:**
```typescript
// Explicitly clear environment variables
delete process.env.ANTHROPIC_BASE_URL;
delete process.env.ANTHROPIC_AUTH_TOKEN;
delete process.env.ANTHROPIC_API_KEY;

// Then configure client
const client = new Anthropic({
  baseURL: 'https://lamassu.ita.chalmers.se',
  authToken: GATEWAY_KEY
});
```

#### 3. `404 Model Not Found`

**Problem:** The model name is incorrect or not supported.

**Solution:**
- For Claude: Use `claude-sonnet-4-5`, `claude-haiku-4-5`, or `claude-opus-4-5`
- For GPT: Use `gpt-4`, `gpt-4-turbo`, or `gpt-3.5-turbo`
- Avoid using dated model versions (e.g., don't use `claude-3-5-sonnet-20241022`)

#### 4. Connection Timeout

**Problem:** Request times out before completing.

**Solutions:**
- Check your network connection
- For long-running requests, increase SDK timeout:

```python
# Python
client = Anthropic(
    base_url="https://lamassu.ita.chalmers.se",
    api_key="dummy",
    default_headers={"Authorization": f"Bearer {GATEWAY_KEY}"},
    timeout=60.0  # 60 seconds
)
```

```typescript
// TypeScript
const client = new Anthropic({
  baseURL: 'https://lamassu.ita.chalmers.se',
  authToken: GATEWAY_KEY,
  timeout: 60000  // 60 seconds
});
```

---

## Best Practices

### 1. Environment Variables

Store your API key in environment variables, never in code:

```bash
# .env file (DO NOT COMMIT TO GIT)
GATEWAY_API_KEY=SK7rDUgRws1HibQ-XQv9FBOBGXBdPb0p_RGE7fDhX74
```

**.gitignore:**
```
.env
*.env
.env.*
```

**Load in Python:**
```python
from dotenv import load_dotenv
import os

load_dotenv()
GATEWAY_KEY = os.getenv("GATEWAY_API_KEY")
```

**Load in TypeScript:**
```typescript
import * as dotenv from 'dotenv';
dotenv.config();

const GATEWAY_KEY = process.env.GATEWAY_API_KEY || '';
```

### 2. Error Handling

Always handle API errors gracefully:

```python
from anthropic import APIError, APIConnectionError

try:
    message = client.messages.create(...)
except APIConnectionError as e:
    print(f"Network error: {e}")
except APIError as e:
    print(f"API error: {e.status_code} - {e.message}")
```

```typescript
try {
  const message = await client.messages.create(...);
} catch (error: any) {
  if (error.status) {
    console.error(`API error: ${error.status} - ${error.message}`);
  } else {
    console.error(`Network error: ${error.message}`);
  }
}
```

### 3. Token Management

Monitor your token usage to optimize costs:

```python
# Anthropic
message = client.messages.create(...)
print(f"Input tokens: {message.usage.input_tokens}")
print(f"Output tokens: {message.usage.output_tokens}")

# OpenAI
response = client.chat.completions.create(...)
print(f"Total tokens: {response.usage.total_tokens}")
```

### 4. Streaming for Long Responses

Use streaming for better user experience with long responses:

```python
# Anthropic
with client.messages.stream(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Write a long story"}]
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)
```

```typescript
// OpenAI
const stream = await client.chat.completions.create({
  model: 'gpt-4',
  messages: [{ role: 'user', content: 'Write a long story' }],
  stream: true
});

for await (const chunk of stream) {
  process.stdout.write(chunk.choices[0]?.delta?.content || '');
}
```

### 5. Client Reuse

Create the client once and reuse it across requests:

```python
# Good: Create client once
client = Anthropic(
    base_url="https://lamassu.ita.chalmers.se",
    api_key="dummy",
    default_headers={"Authorization": f"Bearer {GATEWAY_KEY}"}
)

# Make multiple requests
response1 = client.messages.create(...)
response2 = client.messages.create(...)

# Bad: Creating new client for each request (inefficient)
def get_response(prompt):
    client = Anthropic(...)  # Don't do this!
    return client.messages.create(...)
```

### 6. Model Selection

Choose the appropriate model for your use case:

- **Quick responses:** `claude-haiku-4-5` or `gpt-3.5-turbo`
- **Balanced performance:** `claude-sonnet-4-5` or `gpt-4`
- **Complex reasoning:** `claude-opus-4-5` or `gpt-4-turbo`
- **Long context:** `claude-sonnet-4-5` (200K) or `gpt-4-turbo` (128K)

---

## Complete Setup Example

Here's a complete, production-ready setup:

### Python Project Structure
```
my-project/
├── .env                 # API key (gitignored)
├── .gitignore
├── requirements.txt
└── main.py
```

**requirements.txt:**
```
anthropic==0.39.0
openai==1.54.0
python-dotenv==1.0.0
```

**.env:**
```
GATEWAY_API_KEY=your_gateway_key_here
```

**.gitignore:**
```
.env
__pycache__/
*.pyc
```

**main.py:**
```python
from anthropic import Anthropic, APIError
from openai import OpenAI
from dotenv import load_dotenv
import os

# Load environment variables
load_dotenv()
GATEWAY_KEY = os.getenv("GATEWAY_API_KEY")

if not GATEWAY_KEY:
    raise ValueError("GATEWAY_API_KEY not found in environment")

# Create clients (reuse these)
anthropic_client = Anthropic(
    base_url="https://lamassu.ita.chalmers.se",
    api_key="dummy",
    default_headers={"Authorization": f"Bearer {GATEWAY_KEY}"}
)

openai_client = OpenAI(
    base_url="https://lamassu.ita.chalmers.se/v1",
    api_key=GATEWAY_KEY
)

def chat_with_claude(prompt: str) -> str:
    """Send a message to Claude via gateway"""
    try:
        message = anthropic_client.messages.create(
            model="claude-sonnet-4-5",
            max_tokens=1024,
            messages=[{"role": "user", "content": prompt}]
        )
        return message.content[0].text
    except APIError as e:
        return f"Error: {e.status_code} - {e.message}"

def chat_with_gpt(prompt: str) -> str:
    """Send a message to GPT via gateway"""
    try:
        response = openai_client.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": prompt}]
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Error: {str(e)}"

# Example usage
if __name__ == "__main__":
    print(chat_with_claude("What is the capital of France?"))
    print(chat_with_gpt("What is the capital of Spain?"))
```

---

## Support & Questions

For gateway-related issues:
- Check this documentation first
- Review the [troubleshooting section](#troubleshooting)
- Contact your gateway administrator

For SDK-specific questions:
- [Anthropic Documentation](https://docs.anthropic.com/)
- [OpenAI Documentation](https://platform.openai.com/docs/)

---

**Document Version:** 1.0
**Last Updated:** 2026-01-14
**Gateway Version:** APISIX 3.14.1
