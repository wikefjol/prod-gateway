# Getting Started

The AI Gateway gives you access to OpenAI, Anthropic, and vLLM models with your Chalmers account.

## 1. Sign in & get your API key

Go to the [Portal](/portal/){:target="_blank"} and sign in with your **Chalmers credentials** (Microsoft SSO). Click **Get Key** — your key is shown once.

!!! warning
    Store your key somewhere safe. If you lose it, regenerate it in the portal — the old key is immediately invalidated.

## 2. Start chatting in Open WebUI

The easiest way to use the gateway is through [Open WebUI](https://openwebui.portal.chalmers.se){:target="_blank"} — a browser-based chat interface.

1. Open [Open WebUI](https://openwebui.portal.chalmers.se){:target="_blank"}
2. Add a **Direct Connection** ([guide](https://docs.openwebui.com/features/chat-conversations/direct-connections/#user-configuration){:target="_blank"}):
    - **Base URL**: `https://ai-gateway.portal.chalmers.se/llm/openai/v1`
    - **Key**: your API key
3. Pick a model and chat

One key works for all models — routing is automatic based on the model you select.

## 3. Want API access?

Use the same key and base URL with any OpenAI-compatible SDK or tool:

```bash
export OPENAI_API_KEY="YOUR_API_KEY"
export OPENAI_BASE_URL="https://ai-gateway.portal.chalmers.se/llm/openai/v1"
```

- [SDK Examples](sdk-examples.md) — Python, JavaScript, cURL
- [Coding Agents](coding-agents.md) — configure AI coding tools to use the gateway
