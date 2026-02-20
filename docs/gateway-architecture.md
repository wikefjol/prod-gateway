# APISIX Gateway Architecture Reference

This document describes the current state of the LLM API Gateway built on Apache APISIX. It answers common questions about auth, routing, consumers, and infrastructure for developers unfamiliar with the setup.

---

## Architecture Overview

See [diagrams.md](diagrams.md) for visual request/response flow diagrams.

### Routing Paths

| Path | Route | Plugins | Upstream | TTFT Overhead |
|------|-------|---------|----------|---------------|
| **ai-proxy** | `/llm/ai-proxy/v1/*` | model-policy → ai-proxy → provider-response-id | Direct to OpenAI/Anthropic | ~2% |
| **litellm** | `/llm/litellm/v1/*` | proxy-rewrite → billing-extractor → provider-response-id | LiteLLM server | ~3x |
| **claude-code** | `/llm/claude-code/v1/*` | consumer-restriction → billing-extractor | Direct to Anthropic | ~10% |

### Billing Log Schema (Unified)

All paths log to `logs/billing/*.log`:

```json
{
  "timestamp": "$time_iso8601",
  "gw_request_id": "$request_id",
  "provider_response_id": "$provider_response_id",
  "consumer": "$consumer_name",
  "route_name": "$route_name",
  "model_effective": "$llm_model",
  "model_requested": "$request_llm_model",
  "prompt_tokens": "$llm_prompt_tokens",
  "completion_tokens": "$llm_completion_tokens",
  "status": "$status"
}
```

### Custom Plugins

| Plugin | Purpose | Phase |
|--------|---------|-------|
| `auth-transform` | Bearer → x-api-key header | rewrite |
| `model-policy` | Enforce allowed models per consumer | access |
| `billing-extractor` | Parse SSE for usage data | access + body_filter |
| `provider-response-id` | Extract response ID from stream | body_filter |
| `response-wiretap` | Debug capture (gated by X-Debug-Capture header) | body_filter + log |

---

## Table of Contents

1. [Auth Normalization / Identity Source](#1-auth-normalization--identity-source)
2. [Key-Auth + Consumer Mapping](#2-key-auth--consumer-mapping)
3. [Consumer Groups](#3-consumer-groups)
4. [Current Route Layout](#4-current-route-layout)
5. [Provider Routing Method](#5-provider-routing-method)
6. [ai-proxy Plugin Usage](#6-ai-proxy-plugin-usage)
7. [Upstream Configuration](#7-upstream-configuration)
8. [Streaming Behavior](#8-streaming-behavior)
9. [/models Current Behavior](#9-models-current-behavior)
10. [IaC/Bootstrapping Constraints](#10-iacbootstrapping-constraints)

---

## 1. Auth Normalization / Identity Source

**Question**: Are we normalizing `Authorization: Bearer <token>` into whatever APISIX uses for `key-auth` / consumer lookup?

**Answer**: Yes. The gateway accepts both `Authorization: Bearer <token>` and `X-Api-Key: <token>` headers. Bearer tokens are transformed to `X-Api-Key` before the `key-auth` plugin runs.

**Implementation**: Custom Lua module loaded via `serverless-pre-function`.

**File**: `services/apisix/lua/apisix/plugins/auth-transform.lua`

```lua
local core = require("apisix.core")
local M = {}

function M.bearer_to_api_key(conf, ctx)
  -- Get the existing x-api-key header
  local api_key = core.request.header(ctx, "x-api-key")

  -- Get the Authorization header
  local auth_header = core.request.header(ctx, "Authorization")

  -- Case 1: If X-Api-Key exists and non-empty
  if api_key and api_key ~= "" then
    -- Do NOT overwrite it from Authorization
    -- Just remove Authorization to avoid conflicts but preserve the existing X-Api-Key
    if auth_header then
      core.request.set_header(ctx, "Authorization", nil)
    end
  -- Case 2: If X-Api-Key is missing but Authorization exists and is Bearer format
  elseif auth_header and auth_header:sub(1, 7) == 'Bearer ' then
    -- Extract the token part after "Bearer "
    local token = auth_header:sub(8)

    -- Set it as x-api-key header
    core.request.set_header(ctx, "x-api-key", token)

    -- Remove the Authorization header to avoid conflicts
    core.request.set_header(ctx, "Authorization", nil)
  end
end

return M
```

**Invocation in routes** (via `serverless-pre-function` with high priority so it runs before `key-auth`):

```json
{
  "serverless-pre-function": {
    "_meta": { "priority": 12020 },
    "phase": "rewrite",
    "functions": [
      "return function(conf, ctx) local auth = require('apisix.plugins.auth-transform') auth.sanitize_request_ids(conf, ctx) return auth.bearer_to_api_key(conf, ctx) end"
    ]
  }
}
```

**Note**: The `_meta.priority` of 12020 ensures this runs before `key-auth` (priority 2500).

---

## 2. Key-Auth + Consumer Mapping

**Question**: What plugin(s) are used for auth? How is Bearer token mapped to an APISIX consumer?

**Answer**:

- **Plugin**: `key-auth` with header `x-api-key`
- **Consumer creation**: Via APISIX Admin API. Each consumer has a `key-auth` plugin with a `key` field.
- **Management**: The Portal service (`services/portal/src/app.py`) handles consumer CRUD operations.

**Route plugin config**:

```json
{
  "key-auth": {
    "header": "x-api-key",
    "hide_credentials": true
  }
}
```

**Consumer object structure** (created via Admin API):

```json
{
  "username": "user@example.com",
  "group_id": "base_user",
  "plugins": {
    "key-auth": {
      "key": "user-provided-or-generated-api-key"
    }
  }
}
```

**Flow**:
1. Client sends `Authorization: Bearer sk-abc123` or `X-Api-Key: sk-abc123`
2. `auth-transform.lua` normalizes to `X-Api-Key: sk-abc123`
3. `key-auth` plugin looks up consumer by matching the key
4. Consumer context (username, group_id) is attached to request

---

## 3. Consumer Groups

**Question**: Are consumer groups created and linked to consumers? What field is used at runtime?

**Answer**: Yes. Two consumer groups exist with rate limiting policies.

**Files**: `services/apisix/consumer-groups/*.json`

| Group ID | Weekly Quota | Purpose |
|----------|--------------|---------|
| `base_user` | 1,000,000 requests | Default tier |
| `premium_user` | 1,000,000 requests | Elevated tier |

**Example** (`base-user-group.json`):

```json
{
  "id": "base_user",
  "plugins": {
    "limit-count": {
      "count": 1000000,
      "time_window": 604800,
      "rejected_code": 429,
      "rejected_msg": "Weekly quota exceeded. Limit resets every 7 days. Contact admin for upgrade.",
      "key_type": "var",
      "key": "consumer_name",
      "show_limit_quota_header": true
    }
  }
}
```

**Runtime access**:
- `consumer_group_id` - available in APISIX context (`ctx.consumer_group_id`)
- `consumer_name` - the username from consumer object
- Can be used in `vars` conditions, Lua plugins, or logging

**Linking**: Consumers are linked via the `group_id` field when created:

```json
{
  "username": "alice@example.com",
  "group_id": "base_user",
  ...
}
```

---

## 4. Current Route Layout

**Question**: Which endpoints exist under `/llm/*`?

### LLM API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/llm/ai-proxy/v1/chat/completions` | POST | Model-routed to OpenAI or Anthropic via ai-proxy |
| `/llm/ai-proxy/v1/models` | GET | Model list filtered by consumer group |
| `/llm/litellm/v1/chat/completions` | POST | Proxied to LiteLLM service |
| `/llm/litellm/v1/models` | GET | Model list from LiteLLM |
| `/llm/claude-code/v1/messages` | POST | Native Anthropic Messages API |
| `/llm/claude-code/v1/messages/count_tokens` | POST | Token counting |

### Other Routes

| Endpoint | Description |
|----------|-------------|
| `/health` | Health check |
| `/portal`, `/portal/*` | Portal UI (OIDC-protected) |
| `/` | Redirect to portal |

**All route files**: `services/apisix/routes/`

```
health-route.json
llm-ai-proxy-chat-anthropic.json
llm-ai-proxy-chat-openai.json
llm-ai-proxy-models.json
llm-claude-code-count-tokens.json
llm-claude-code-messages.json
llm-litellm-chat.json
llm-litellm-models.json
oidc-generic-route.json
portal-redirect-route.json
root-redirect-route.json
```

---

## 5. Provider Routing Method

**Question**: How does routing work? What APISIX version?

**Answer**:

- **Method**: `vars` with `post_arg.model` regex matching
- **APISIX Version**: 3.15.0-debian (from `Dockerfile`)
- **Mechanism**: Multiple routes share the same URI but have different `vars` conditions. Higher `priority` routes are evaluated first.

**How it works**:

```
POST /llm/ai-proxy/v1/chat/completions {"model": "gpt-4o-mini", ...}
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│  Route: llm-ai-proxy-chat-openai (priority: 10)             │
│  vars: [["post_arg.model", "~~", "^(gpt|o1|o3|...)"]]      │
│  → MATCHES → ai-proxy (openai)                              │
└─────────────────────────────────────────────────────────────┘

POST /llm/ai-proxy/v1/chat/completions {"model": "claude-sonnet-4", ...}
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│  Route: llm-ai-proxy-chat-openai (priority: 10)             │
│  vars: [["post_arg.model", "~~", "^(gpt|o1|o3|...)"]]      │
│  → NO MATCH                                                 │
│                                                             │
│  Route: llm-ai-proxy-chat-anthropic (priority: 10)          │
│  vars: [["post_arg.model", "~~", "^claude"]]               │
│  → MATCHES → ai-proxy (anthropic)                           │
└─────────────────────────────────────────────────────────────┘
```

Unknown models are rejected by model-policy plugin (returns 400).

**Route example** (`llm-ai-proxy-chat-openai.json`):

```json
{
  "id": "llm-ai-proxy-chat-openai",
  "uri": "/llm/ai-proxy/v1/chat/completions",
  "methods": ["POST", "OPTIONS"],
  "priority": 10,
  "vars": [["post_arg.model", "~~", "^(gpt|o1|o3|davinci|text-embedding)"]],
  "plugins": {
    "cors": { ... },
    "auth-transform": { "mode": "bearer_to_api_key" },
    "openai-auth": { "header": "x-api-key" },
    "model-policy": { "action": "enforce" },
    "ai-proxy": {
      "provider": "openai",
      "auth": { "header": { "Authorization": "Bearer $OPENAI_API_KEY" } }
    },
    "provider-response-id": {},
    "file-logger": { ... }
  }
}
```

**Key points**:
- `post_arg.model` reads the `model` field from JSON body
- `~~` is regex match operator
- `priority: 10` for provider routes, `priority: 1` for fallback
- Requires APISIX 3.14+ (PR #12388 added `post_arg.*` support)

---

## 6. ai-proxy Plugin Usage

**Question**: Are we using `ai-proxy` for both providers? Does Anthropic return OpenAI-shaped responses?

**Answer**: Yes to both.

- **OpenAI routes**: `ai-proxy` with `provider: openai` (passthrough, already OpenAI format)
- **Anthropic routes**: `ai-proxy` with `provider: anthropic` (translates Anthropic responses to OpenAI format)

**Protocol translation by ai-proxy**:

| Direction | What happens |
|-----------|--------------|
| Request (OpenAI → Anthropic) | Converts OpenAI `messages` format to Anthropic format |
| Response (Anthropic → OpenAI) | Converts Anthropic response to OpenAI `choices` format |
| Streaming | Converts Anthropic SSE events to OpenAI SSE chunk format |

**Anthropic route config**:

```json
{
  "ai-proxy": {
    "provider": "anthropic",
    "auth": {
      "header": {
        "x-api-key": "$ANTHROPIC_API_KEY",
        "anthropic-version": "2023-06-01"
      }
    }
  }
}
```

**Result**: Clients always send/receive OpenAI-format requests/responses regardless of backend provider.

---

## 7. Upstream Configuration

**Question**: Where are upstreams defined? How are API keys injected?

**Answer**:

- **Upstreams**: Defined per-route in `ai-proxy` plugin config. No shared upstream objects.
- **API keys**: Environment variable substitution via `envsubst` during bootstrap.

**Key injection flow**:

1. Keys stored in `infra/env/.env.dev` (or `.env.test`):
   ```bash
   ANTHROPIC_API_KEY=sk-ant-api03-...
   OPENAI_API_KEY=sk-proj-...
   ```

2. Bootstrap script loads env and runs `envsubst`:
   ```bash
   # From bootstrap.sh
   payload="$(envsubst < "$file_path")"
   ```

3. Route JSON uses `$VAR` syntax:
   ```json
   {
     "auth": {
       "header": {
         "Authorization": "Bearer $OPENAI_API_KEY"
       }
     }
   }
   ```

4. After substitution, actual key is PUT to Admin API.

**Note**: Keys are stored in etcd after bootstrap, not in container filesystem.

---

## 8. Streaming Behavior

**Question**: Is streaming verified? Any buffering issues?

**Answer**:

- **Status**: Verified working for both OpenAI and Anthropic via `/llm/ai-proxy/v1/chat/completions`
- **Buffering issues**: None currently known

**Test commands**:

```bash
# OpenAI streaming
curl -N -X POST localhost:9080/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"count 1 to 5"}],"stream":true}'

# Anthropic streaming (returns OpenAI-format SSE)
curl -N -X POST localhost:9080/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-3-5-haiku-20241022","messages":[{"role":"user","content":"count 1 to 5"}],"stream":true}'
```

**Expected output**: SSE stream with `data: {...}` chunks, ending with `data: [DONE]`.

---

## 9. /models Current Behavior

**Question**: What does `/llm/ai-proxy/v1/models` return? Is it filtered by consumer/group?

**Answer**:

- **Implementation**: Dynamic model list via `model-policy` plugin with `action=render`
- **Filtering**: Yes. Consumer group determines which models are visible.
- **Format**: OpenAI-compatible `/v1/models` response

**Route** (`llm-ai-proxy-models.json`):

```json
{
  "id": "llm-ai-proxy-models",
  "uri": "/llm/ai-proxy/v1/models",
  "methods": ["GET", "OPTIONS"],
  "plugins": {
    "cors": { ... },
    "auth-transform": { ... },
    "openai-auth": { ... },
    "model-policy": { "action": "render" }
  }
}
```

Model list is defined in `model-policy.lua` (MODEL_REGISTRY) and filtered by consumer group.

---

## 10. IaC/Bootstrapping Constraints

**Question**: Where should policy data live? Any constraints on implementation approach?

### Current Approach

- **Route definitions**: JSON files in `services/apisix/routes/`
- **Consumer groups**: JSON files in `services/apisix/consumer-groups/`
- **Plugin metadata**: JSON files in `services/apisix/plugin-metadata/`
- **Bootstrap**: `services/apisix/scripts/bootstrap.sh` PUTs everything to Admin API

**Bootstrap script structure**:

```bash
CORE_CONSUMER_GROUPS=(
  "base-user-group.json"
  "premium-user-group.json"
)

CORE_ROUTES=(
  "health-route.json"
  "portal-redirect-route.json"
  ...
)

LLM_ROUTES=(
  "llm-ai-proxy-chat-openai.json"
  "llm-ai-proxy-chat-anthropic.json"
  "llm-ai-proxy-models.json"
  "llm-litellm-chat.json"
  "llm-litellm-models.json"
  "llm-claude-code-messages.json"
  "llm-claude-code-count-tokens.json"
)
```

### Constraints / Preferences

| Constraint | Status |
|------------|--------|
| Serverless Lua allowed | ✅ Yes (already used for auth-transform, static responses) |
| Complex Lua in separate files | ✅ Preferred - put in `services/apisix/lua/apisix/plugins/` |
| Pure JSON routes | ✅ Preferred for simple config |
| Avoid too many routes | ⚠️ Soft preference - current count ~20 routes |
| No external dependencies | ✅ No Redis, no external policy service |

### Adding New Policy Data

**Option A: Static in route JSON**
- Pros: Simple, no extra files
- Cons: Hard to maintain, no filtering

**Option B: Lua module with data file**
- Put data in `services/apisix/lua/apisix/plugins/my-policy.lua`
- Load via `require()` in serverless function
- Pros: Maintainable, can add logic
- Cons: Requires rebuild to update

**Option C: External JSON loaded at runtime**
- Mount JSON file into container
- Read via Lua `io.open()` or cache
- Pros: Update without rebuild
- Cons: More complexity

**Recommendation**: For model registry / group allowlists, use **Option B** (Lua module) if logic is needed, or keep in route JSON if purely static.

---

## Directory Structure Reference

```
services/apisix/
├── compose.yaml              # Docker compose (includes etcd)
├── Dockerfile                # APISIX 3.15.0-debian base
├── config.yaml               # APISIX config (plugins list, admin keys)
├── entrypoint-simple.sh      # Container entrypoint
├── routes/                   # Route JSON files
│   ├── llm-ai-proxy-chat-openai.json
│   ├── llm-ai-proxy-chat-anthropic.json
│   ├── llm-ai-proxy-models.json
│   ├── llm-litellm-*.json
│   ├── llm-claude-code-*.json
│   └── ...
├── consumer-groups/          # Consumer group JSON files
│   ├── base-user-group.json
│   └── premium-user-group.json
├── plugin-metadata/          # Plugin metadata JSON files
│   └── file-logger.json
├── scripts/
│   └── bootstrap.sh          # Loads all config to Admin API
└── lua/apisix/plugins/       # Custom Lua modules
    ├── auth-transform.lua    # Bearer → X-Api-Key transform
    └── billing-extractor.lua # Usage extraction for logging

infra/
├── env/
│   ├── .env.dev              # Dev environment (API keys, ports)
│   └── .env.test             # Test environment
└── ctl/
    └── ctl.sh                # Unified control script (up/down/reset/bootstrap)
```

---

## Quick Commands

```bash
# Start services
./infra/ctl/ctl.sh up

# Restart + reload routes
./infra/ctl/ctl.sh reset

# Bootstrap routes only (no restart)
./infra/ctl/ctl.sh bootstrap

# View logs
./infra/ctl/ctl.sh logs apisix -f

# List routes
./infra/ctl/ctl.sh routes
```
