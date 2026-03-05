# Getting Started

The AI Gateway provides unified access to OpenAI, Anthropic, and Alvis vLLM models through a single API endpoint with Chalmers SSO authentication.

## 1. Sign in & get your API key

1. Go to the [Portal](/portal/)
2. Sign in with your **Chalmers credentials** (Microsoft SSO)
3. Click **Get Key** — your key is displayed once and stored securely

!!! warning
    Store your key somewhere safe. If you lose it, you can regenerate it in the portal — but the old key is immediately invalidated.

## 2. Make your first API call

All requests go through a single base URL:

```
https://ai-gateway.portal.chalmers.se/llm/openai/v1
```

=== "cURL"

    ```bash
    curl https://ai-gateway.portal.chalmers.se/llm/openai/v1/chat/completions \
      -H "Authorization: Bearer YOUR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "gpt-4o-mini",
        "messages": [{"role": "user", "content": "Hello!"}]
      }'
    ```

=== "Python"

    ```python
    from openai import OpenAI

    client = OpenAI(
        api_key="YOUR_API_KEY",
        base_url="https://ai-gateway.portal.chalmers.se/llm/openai/v1"
    )

    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": "Hello!"}]
    )
    print(response.choices[0].message.content)
    ```

## 3. Available models

To see available models use:

```bash
curl https://ai-gateway.portal.chalmers.se/llm/openai/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"
```

## 4. Authentication

Every request requires a Bearer token:

```
Authorization: Bearer YOUR_API_KEY
```

One key works for all models and endpoints. Routing is automatic based on the `model` field.

## Next steps

- [SDK Examples](sdk-examples.md) — Python, JavaScript, cURL code snippets
- [Coding Agents](coding-agents.md) — configure AI coding tools to use the gateway
- [OpenWebUI](openwebui.md) — Browser-based chat interface
