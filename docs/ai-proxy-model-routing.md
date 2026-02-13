# AI Proxy: Model-Based Routing

## Problem

We have an LLM API gateway (Apache APISIX) that proxies requests to multiple AI providers (OpenAI, Anthropic). We want a **single unified endpoint** (`/llm/ai-proxy/v1/chat/completions`) that automatically routes requests to the correct provider based on the model name in the request body.

Example: A client sends `{"model": "gpt-4o-mini", ...}` → route to OpenAI. A client sends `{"model": "claude-sonnet-4-20250514", ...}` → route to Anthropic.

## Why Not LiteLLM or ai-proxy-multi?

- **LiteLLM**: Adds another service to maintain. We want routing at the gateway level.
- **ai-proxy-multi**: APISIX plugin that load-balances between provider instances. It does NOT auto-route by model name - it randomly picks a provider, which fails when the model doesn't exist on that provider.

## Solution

Use APISIX's `vars` route matching with `post_arg.model` to inspect the JSON request body and route based on model name patterns. Create separate routes for each provider, same URI, different `vars` conditions.

```
POST /llm/ai-proxy/v1/chat/completions {"model": "gpt-4o-mini", ...}
                │
                ▼
┌─────────────────────────────────────────────────────────────┐
│  APISIX Route Matching (by vars)                            │
│                                                             │
│  Route: llm-ai-proxy-chat-openai (priority: 10)                       │
│    uri: /llm/ai-proxy/v1/chat/completions                             │
│    vars: [["post_arg.model", "~~", "^(gpt|o1|o3|davinci)"]]│
│    plugins: ai-proxy (provider: openai)                     │
│                                                             │
│  Route: llm-ai-proxy-chat-anthropic (priority: 10)                    │
│    uri: /llm/ai-proxy/v1/chat/completions                             │
│    vars: [["post_arg.model", "~~", "^claude"]]             │
│    plugins: ai-proxy (provider: anthropic)                  │
│                                                             │
│  (model-policy plugin rejects unknown models with 400)  │
└─────────────────────────────────────────────────────────────┘
                │
                ▼
        Correct Provider API
```

## Key Concepts

### post_arg.model
APISIX can match on JSON body fields using `post_arg.<field>`. Available since APISIX 3.14 (PR #12388). The `~~` operator does regex matching.

### Route Priority
Multiple routes can have the same URI. APISIX matches the route with highest `priority` value first. If `vars` conditions don't match, it tries the next route.

- Provider routes: priority 10 (checked first)
- Unknown models: rejected by model-policy plugin

### ai-proxy Plugin
APISIX's built-in plugin that proxies to a single LLM provider. Handles:
- Protocol translation (OpenAI format ↔ Anthropic format)
- Auth header injection
- Streaming support

## Files

```
services/apisix/routes/
├── llm-ai-proxy-chat-openai.json      # Routes gpt-*, o1-*, o3-*, davinci-*, text-embedding-*
├── llm-ai-proxy-chat-anthropic.json   # Routes claude-*
└── llm-ai-proxy-models.json           # GET /llm/ai-proxy/v1/models - model list
```

Note: Unknown models are rejected by `model-policy` plugin (no separate fallback route).

## Route Structure Example

```json
{
  "id": "llm-ai-proxy-chat-openai",
  "uri": "/llm/ai-proxy/v1/chat/completions",
  "methods": ["POST"],
  "priority": 10,
  "vars": [["post_arg.model", "~~", "^(gpt|o1|o3|davinci|text-embedding)"]],
  "plugins": {
    "key-auth": { "header": "x-api-key" },
    "ai-proxy": {
      "provider": "openai",
      "auth": { "header": { "Authorization": "Bearer $OPENAI_API_KEY" } }
    }
  }
}
```

## Adding a New Provider

1. Create `services/apisix/routes/ai-chat-<provider>.json`
2. Set appropriate `vars` regex to match model names
3. Configure `ai-proxy` with provider name and auth
4. Add to `PROVIDER_ROUTES` array in `services/apisix/scripts/bootstrap.sh`
5. Update `llm-ai-proxy-models.json` to include new models
6. Run `./infra/ctl/ctl.sh bootstrap`

## Testing

```bash
# OpenAI model
curl -X POST localhost:9080/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}'

# Anthropic model (returns OpenAI-format response via ai-proxy)
curl -X POST localhost:9080/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-20250514","messages":[{"role":"user","content":"hi"}]}'

# Unknown model (returns 400)
curl -X POST localhost:9080/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"unknown-model","messages":[{"role":"user","content":"hi"}]}'

# List available models
curl localhost:9080/llm/ai-proxy/v1/models -H "Authorization: Bearer $API_KEY"
```

## Related

- APISIX ai-proxy plugin: https://apisix.apache.org/docs/apisix/plugins/ai-proxy/
- post_arg support PR: https://github.com/apache/apisix/pull/12388
