# FAQ

## Getting Started

??? question "How do I get an API key?"
    Visit the [Portal](/portal/) and sign in with your Chalmers credentials. Click **Get Key** to generate your API key.

??? question "Can I use the same key for all models?"
    Yes. One key works for all endpoints and models. The gateway routes automatically based on the `model` field in your request.

??? question "What if I lose my key?"
    Go to the [Portal](/portal/) and click **Recycle Key** to generate a new one. The old key is immediately invalidated.

## OpenWebUI

??? question "How do I access OpenWebUI?"
    Go to [openwebui.portal.chalmers.se](https://openwebui.portal.chalmers.se) and sign in with your Chalmers credentials.

??? question "Where are my conversations stored?"
    Conversation history is stored in your browser. It is not accessible to administrators or other users.

## API & SDKs

??? question "Which SDK should I use?"
    Use the **OpenAI Python SDK** for most use cases — it works with all models (OpenAI, Anthropic, vLLM) through the gateway's unified endpoint. See [SDK Examples](sdk-examples.md).

??? question "Does streaming work?"
    Yes. All endpoints support streaming. Pass `stream=True` in your request and optionally `stream_options={"include_usage": True}` for token usage tracking.

??? question "Can I use the Anthropic SDK directly?"
    Yes, but only through the Claude Code sidecar endpoint (`/llm/claude-code/v1`), which requires `claude_code_users` group membership. For most users, the OpenAI SDK with the ai-proxy endpoint is simpler.

## Coding Agents

??? question "Which coding agents are supported?"
    Claude Code, Cursor, Continue.dev, and Aider are tested. Any OpenAI-compatible tool should work — set the base URL and API key. See [Coding Agents](coding-agents.md).

??? question "Claude Code says 'unauthorized' — what's wrong?"
    Claude Code uses the `/llm/claude-code/v1` endpoint which requires the `claude_code_users` consumer group. Contact the administrator for access.

## Security & Privacy

??? question "Who can see my requests?"
    The gateway logs request metadata (model, token count, timestamps) for billing and monitoring. Message content is **not** logged. Requests are forwarded to the model provider (OpenAI, Anthropic, or Alvis HPC).

??? question "Is my data sent outside Chalmers?"
    For OpenAI and Anthropic models, yes — requests are sent to their APIs. For Alvis vLLM models, requests stay within the Chalmers/C3SE infrastructure.

??? question "Can other users see my API key?"
    No. Keys are stored in the gateway's internal database and are only visible to the key owner through the Portal.

## Errors & Troubleshooting

??? question "I get a 404 error"
    Check that your request URL includes `/llm/ai-proxy/v1/` — not `/v1/`. Also verify the model name matches an available model exactly.

??? question "I get a 502 error"
    The upstream provider is temporarily unavailable. Wait a few seconds and retry. See [Error Reference](error-reference.md#502-bad-gateway).

??? question "My key stopped working"
    You may have recycled it in the Portal. Go to the [Portal](/portal/) to get your current key.
