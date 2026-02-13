# Gateway Polish Sprint Plan

Prepare the LLM API Gateway for formal comparison testing between two routing approaches, plus a Claude Code sidecar.

## Problem Statement

The gateway currently has scattered routes across `/ai/*`, `/openwebui/*`, `/provider/*` with inconsistent plugin configurations, inline Lua code, and no clear separation between the two architectural approaches we want to compare:

- **Setup A (LiteLLM)**: External service handles model→provider routing
- **Setup B (ai-proxy)**: APISIX-native routing via ai-proxy plugin

Additionally, Claude Code requires native Anthropic protocol which neither approach can provide - requiring a dedicated sidecar.

**Goal**: Clean, comparable implementations of both setups + sidecar, with consistent logging, proper plugin architecture, and clear namespace separation.

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        /llm/* namespace                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  /llm/litellm/v1/*          /llm/ai-proxy/v1/*     /llm/claude-code/*   │
│  ┌─────────────────┐        ┌─────────────────┐    ┌─────────────────┐  │
│  │ Setup A         │        │ Setup B         │    │ Sidecar         │  │
│  │                 │        │                 │    │                 │  │
│  │ → LiteLLM       │        │ → ai-proxy      │    │ → Anthropic     │  │
│  │   (external)    │        │   (APISIX)      │    │   (native)      │  │
│  │                 │        │                 │    │                 │  │
│  │ Streaming:      │        │ Streaming:      │    │ Streaming:      │  │
│  │ preserves       │        │ forces          │    │ preserves       │  │
│  │ client semantics│        │ include_usage   │    │ client semantics│  │
│  └─────────────────┘        └─────────────────┘    └─────────────────┘  │
│           │                          │                      │           │
│           └──────────────────────────┴──────────────────────┘           │
│                                      │                                  │
│                         Consistent Logging Format                       │
│                         (file-logger + wiretap)                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Endpoints

| Namespace | Endpoints | Backend |
|-----------|-----------|---------|
| `/llm/litellm/v1/` | `chat/completions` (POST), `models` (GET) | LiteLLM service |
| `/llm/ai-proxy/v1/` | `chat/completions` (POST), `models` (GET) | ai-proxy → OpenAI/Anthropic |
| `/llm/claude-code/v1/` | `messages` (POST), `messages/count_tokens` (POST) | api.anthropic.com |

### Client Base URLs

| Client | Base URL |
|--------|----------|
| OpenAI SDK → LiteLLM | `https://gateway/llm/litellm/v1` |
| OpenAI SDK → ai-proxy | `https://gateway/llm/ai-proxy/v1` |
| Claude Code | `https://gateway/llm/claude-code` |

## Issues & Dependencies

### Issue Map

```
#18 Namespace reorganization ─────────────────────────────────┐
         │                                                    │
         ▼                                                    │
#22 Extract inline Lua to plugins                             │
         │                                                    │
         ├──────────────┬──────────────┬──────────────────────┤
         ▼              ▼              ▼                      │
#19 Polish         #20 Polish     #21 Polish                  │
    LiteLLM            ai-proxy       Claude Code             │
         │              │              │                      │
         └──────────────┴──────────────┘                      │
                        │                                     │
                        ▼                                     │
              End-to-end validation                           │
                                                              │
#14 file-logger ctx vars ─────────────────────────────────────┤
#15 ID traceability ──────────────────────────────────────────┤
#16 CORS review ──────────────────────────────────────────────┤
#17 HTTP methods audit ───────────────────────────────────────┘
                        │
#23 ctl.sh review ──────┘ (independent, DevEx)
```

### Execution Phases

| Phase | Issues | Description |
|-------|--------|-------------|
| **Phase 1: Foundation** | #18, #22 | Create namespace structure, convert inline Lua to proper plugins |
| **Phase 2: Cross-cutting** | #14, #15, #16, #17 | Define logging format, ID strategy, CORS, HTTP methods |
| **Phase 3: Polish** | #19, #20, #21 | Apply all standards to each setup |
| **Phase 4: DevEx** | #23 | Fix ctl.sh for iteration workflow |
| **Phase 5: Validation** | — | End-to-end testing, comparison readiness |

### Issue Details

| # | Title | Owner | Depends on | Outputs |
|---|-------|-------|------------|---------|
| #14 | file-logger ctx vars | — | — | Canonical log format definition |
| #15 | ID traceability | — | — | ID strategy: `gw_request_id` + `provider_response_id` |
| #16 | CORS review | — | — | CORS policy per route |
| #17 | HTTP methods audit | — | — | Allowed methods per route |
| #18 | Namespace reorganization | — | — | New route files under `/llm/*` |
| #19 | LiteLLM polish | — | #18, #22, #14, #15, #16, #17 | Production-ready Setup A |
| #20 | ai-proxy polish | — | #18, #22, #14, #15, #16, #17 | Production-ready Setup B |
| #21 | Claude Code sidecar | — | #18, #22, #14, #15, #16, #17 | Production-ready sidecar |
| #22 | Extract inline Lua | — | — | Proper APISIX plugins: auth-transform, model-policy, provider-response-id |
| #23 | ctl.sh review | — | — | Working rebuild/restart workflow |

## Contracts

### Contract 1: Canonical Log Format

**All routes MUST log these fields** (null allowed if unavailable):

```json
{
  "timestamp": "$time_iso8601",
  "gw_request_id": "$request_id",
  "consumer": "$consumer_name",
  "consumer_group_id": "$consumer_group_id",
  "route_name": "$route_name",
  "upstream_provider": "$billing_provider",
  "request_type": "$request_type",
  "model_requested": "$request_llm_model",
  "model_effective": "$llm_model",
  "prompt_tokens": "$llm_prompt_tokens",
  "completion_tokens": "$llm_completion_tokens",
  "ttft_ms": "$llm_time_to_first_token",
  "status": "$status",
  "upstream_latency": "$upstream_response_time",
  "provider_response_id": "$billing_provider_response_id"
}
```

**Variable source by route type:**

| Variable | ai-proxy routes | LiteLLM/Claude Code routes |
|----------|-----------------|---------------------------|
| `$billing_provider` | Set by billing-extractor conf | Set by billing-extractor conf |
| `$request_type` | Set by ai-proxy | Set by billing-extractor |
| `$request_llm_model` | Set by ai-proxy | Set by billing-extractor (from req body) |
| `$llm_model` | Set by ai-proxy | Set by billing-extractor (from resp) |
| `$llm_prompt_tokens` | Set by ai-proxy | **#22: billing-extractor must set** |
| `$llm_completion_tokens` | Set by ai-proxy | **#22: billing-extractor must set** |
| `$llm_time_to_first_token` | Set by ai-proxy | (not extracted) |
| `$billing_provider_response_id` | **#22: provider-response-id must set** | Set by billing-extractor |

**NOTE for #22**: billing-extractor must register and set `$llm_prompt_tokens`, `$llm_completion_tokens`, `$request_llm_model`, `$llm_model` to unify logging across all route types. Alternatively, create an adapter plugin.

### Contract 2: MODEL_REGISTRY (Single Source of Truth)

**Location**: `services/apisix/lua/apisix/plugins/model-policy.lua`

```lua
local MODEL_REGISTRY = {
  { id = "gpt-4o", provider = "openai", owned_by = "system", created = 1715367049 },
  { id = "gpt-4o-mini", provider = "openai", owned_by = "system", created = 1721172741 },
  { id = "claude-3-5-sonnet-20241022", provider = "anthropic", owned_by = "anthropic", created = 1729555200 },
  -- ... etc
}
```

**Rules:**
- All model validation checks MODEL_REGISTRY
- `/models` endpoint renders from MODEL_REGISTRY (filtered by consumer group)
- ai-proxy routes: model-policy determines `provider` field for routing
- **NO duplicate model lists** in route JSON (no regex `vars` matching)
- Adding a model = one place only

### Contract 3: Consumer Groups & Access Control

**Consumer groups**: `services/apisix/consumer-groups/*.json`

| Group | Models allowed | Rate limit |
|-------|----------------|------------|
| `base_user` | gpt-4o-mini, claude-3-5-haiku-20241022 | 10k/week |
| `premium_user` | `"*"` (all MODEL_REGISTRY) | 50k/week |
| `claude_code_users` | (sidecar access only) | TBD |

**Access control location**: `model-policy.lua` → `ALLOWED_MODELS_BY_GROUP`

**Sidecar bypass prevention**: `/llm/claude-code/*` routes restricted to `claude_code_users` consumer group.

### Contract 4: Plugin Interfaces

After #22, these are proper APISIX plugins with schema:

**auth-transform**
```json
{
  "auth-transform": {
    "mode": "bearer_to_api_key"
  }
}
```

**model-policy**
```json
{
  "model-policy": {
    "action": "enforce"  // or "render" for /models
  }
}
```

**provider-response-id** (NEW)
```json
{
  "provider-response-id": {}
}
```
Extracts `id` field from response body, sets `$provider_response_id` ctx var.

### Contract 5: Streaming Semantics

| Setup | Behavior | Client-visible difference |
|-------|----------|---------------------------|
| LiteLLM | Preserves client semantics (inject+extract+strip if needed) | None (matches direct API) |
| ai-proxy | Forces `include_usage=true` | Every chunk has `"usage": null`, extra usage chunk at end |
| Claude Code | Preserves client semantics | None (matches direct API) |

**This difference is accepted and documented**, not unified.

## Cross-Cutting Concerns

| Concern | Owner issue | Affects | Detail |
|---------|-------------|---------|--------|
| Canonical log format | #14 | #19, #20, #21 | All routes must emit same fields |
| ID strategy | #15 | #19, #20, #21, #22 | `gw_request_id` + `provider_response_id` everywhere |
| MODEL_REGISTRY sync | #20, #22 | #19, #20 | No model lists in route JSON |
| provider_response_id extraction | #22 | #20 | New plugin needed for ai-proxy |
| Sidecar bypass prevention | #21 | — | Consumer group restriction |
| Inline Lua removal | #22 | #18, #19, #20, #21 | All routes use proper plugins |

### ID Strategy (#15)

**Canonical IDs:**

| ID | Source | Purpose |
|----|--------|---------|
| `gw_request_id` | `$request_id` (request-id plugin) | Primary trace ID, returned in `X-Request-Id` header |
| `provider_response_id` | `$billing_provider_response_id` | Correlate with provider dashboards/invoices |

**Requirements:**
- All routes MUST have `request-id` plugin with `include_in_response: true`
- All routes MUST extract provider response ID (via billing-extractor or provider-response-id plugin)

### CORS Policy (#16)

**Decision**: CORS **is enabled** on `/llm/ai-proxy/*` and `/llm/litellm/*` routes for browser-based clients (OpenWebUI).

**Current configuration**:
```json
"cors": {
  "allow_origins": "*",
  "allow_methods": "POST,OPTIONS",
  "allow_headers": "Authorization,Content-Type,X-Request-Id",
  "expose_headers": "X-Request-Id",
  "max_age": 3600
}
```

### HTTP Methods (#17)

**Policy**: Least privilege - only allow methods that the upstream actually supports.

| Route | Methods | Rationale |
|-------|---------|-----------|
| `/llm/*/v1/chat/completions` | POST | LLM inference is stateless POST |
| `/llm/*/v1/models` | GET | Read-only model listing |
| `/llm/claude-code/v1/messages` | POST | Anthropic messages API |
| `/llm/claude-code/v1/messages/count_tokens` | POST | Token counting |

**No DELETE/PUT**: LLM proxy has no stateful resources to modify.
**OPTIONS**: Enabled for CORS preflight on ai-proxy and litellm routes.

## Agent Build Order & Communication

### Phase 1: Foundation (parallel)

**Agent A: Namespace (#18)**
1. Create new route files under `/llm/litellm/`, `/llm/ai-proxy/`, `/llm/claude-code/`
2. Migrate plugin configs from old routes
3. **Output**: Route file paths, confirm endpoints work

**Agent B: Plugins (#22)**
1. Convert auth-transform to proper APISIX plugin
2. Convert model-policy to proper APISIX plugin
3. Create provider-response-id plugin
4. **Output**: Plugin schemas, registration code

**Agent C: Cross-cutting (#14, #15, #16, #17)** (can run parallel)
1. Define canonical log format (#14)
2. Define ID strategy (#15)
3. Audit CORS needs (#16)
4. Audit HTTP methods (#17)
5. **Output**: file-logger log_format JSON, CORS policy, method restrictions

### Phase 2: Polish (after Phase 1)

**Agent D: LiteLLM (#19)**
- Apply all Phase 1 outputs to `/llm/litellm/*` routes
- Verify: logging, IDs, CORS, methods, no inline Lua

**Agent E: ai-proxy (#20)**
- Apply all Phase 1 outputs to `/llm/ai-proxy/*` routes
- Single route with model-policy routing (no regex split)
- Verify: logging (using ai-proxy ctx vars), IDs (using new plugin), no inline Lua

**Agent F: Claude Code (#21)**
- Apply all Phase 1 outputs to `/llm/claude-code/*` routes
- Implement consumer group restriction
- Verify: logging, IDs, no inline Lua

### Phase 3: DevEx (independent)

**Agent G: ctl.sh (#23)**
- Audit current commands
- Implement `rebuild --no-cache` or equivalent
- Document in CLAUDE.md

### Phase 4: Lead Validation

1. Start gateway with all three namespaces
2. Test each endpoint with curl
3. Verify logs match canonical format
4. Verify IDs present in logs
5. Run comparison: same request to LiteLLM vs ai-proxy, compare logs
6. Test Claude Code sidecar
7. Test bypass prevention (regular consumer → sidecar should fail)

## Validation

### Per-Agent Validation

**Namespace Agent (#18)**
```bash
# Verify routes loaded
curl -s http://localhost:9180/apisix/admin/routes -H "X-API-KEY: $ADMIN_KEY" | jq '.list[].value.uri' | grep llm

# Test endpoints respond
curl -s http://localhost:9080/llm/litellm/v1/models -H "Authorization: Bearer $KEY"
curl -s http://localhost:9080/llm/ai-proxy/v1/models -H "Authorization: Bearer $KEY"
```

**Plugins Agent (#22)**
```bash
# Verify plugins registered
curl -s http://localhost:9180/apisix/admin/plugins/list -H "X-API-KEY: $ADMIN_KEY" | grep -E "auth-transform|model-policy|provider-response-id"

# Verify no inline Lua in routes
grep -r "serverless-pre-function\|serverless-post-function" services/apisix/routes/llm-*.json && echo "FAIL: inline Lua found" || echo "PASS"
```

**Polish Agents (#19, #20, #21)**
```bash
# Send test request
curl -X POST http://localhost:9080/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 5}'

# Check logs contain canonical fields
tail -1 /var/log/apisix/billing/ai-proxy-chat.log | jq 'keys'
# Should include: timestamp, gw_request_id, consumer, model_requested, prompt_tokens, etc.

# Check provider_response_id captured
tail -1 /var/log/apisix/billing/ai-proxy-chat.log | jq '.provider_response_id'
# Should be "chatcmpl-xxx", not null
```

### End-to-End Validation (Lead)

```bash
# 1. Start fresh
./infra/ctl/ctl.sh reset

# 2. Test LiteLLM path
curl -X POST http://localhost:9080/llm/litellm/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "Say hi"}], "max_tokens": 10}'

# 3. Test ai-proxy path (same request)
curl -X POST http://localhost:9080/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "Say hi"}], "max_tokens": 10}'

# 4. Compare logs
diff <(tail -1 /var/log/apisix/billing/litellm-chat.log | jq 'keys | sort') \
     <(tail -1 /var/log/apisix/billing/ai-proxy-chat.log | jq 'keys | sort')
# Should be identical field sets

# 5. Test Claude Code sidecar
curl -X POST http://localhost:9080/llm/claude-code/v1/messages \
  -H "x-api-key: $CLAUDE_CODE_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-3-5-haiku-20241022", "max_tokens": 10, "messages": [{"role": "user", "content": "hi"}]}'

# 6. Test bypass prevention (should fail)
curl -X POST http://localhost:9080/llm/claude-code/v1/messages \
  -H "x-api-key: $REGULAR_USER_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-3-5-haiku-20241022", "max_tokens": 10, "messages": [{"role": "user", "content": "hi"}]}'
# Should return 403 or similar

# 7. Streaming test (verify behavior difference is as documented)
curl -X POST http://localhost:9080/llm/ai-proxy/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "Count to 3"}], "max_tokens": 20, "stream": true}'
# Verify: usage:null on each chunk, usage chunk at end
```

## Acceptance Criteria

- [ ] All routes under `/llm/*` namespace
- [ ] Old routes (`/ai/*`, `/openwebui/*`, `/provider/*`) removed or deprecated
- [ ] No inline Lua in route JSON files
- [ ] MODEL_REGISTRY is single source of truth
- [ ] Canonical log format emitted by all routes
- [ ] `gw_request_id` present in all logs
- [ ] `provider_response_id` present in all logs (including ai-proxy)
- [ ] Wiretap enabled on all routes
- [ ] Claude Code sidecar restricted to dedicated consumer group
- [ ] HTTP methods restricted per route
- [ ] CORS configured where needed
- [ ] Streaming behavior documented (ai-proxy differs, accepted)
- [ ] ctl.sh supports clean rebuild workflow
- [ ] All validation tests pass

## Files Reference

| Category | Path |
|----------|------|
| Routes | `services/apisix/routes/llm-*.json` |
| Custom plugins | `services/apisix/lua/apisix/plugins/*.lua` |
| Plugin metadata | `services/apisix/plugin-metadata/file-logger.json` |
| Consumer groups | `services/apisix/consumer-groups/*.json` |
| Bootstrap script | `services/apisix/scripts/bootstrap.sh` |
| Control script | `infra/ctl/ctl.sh` |
| This plan | `docs/gateway-sprint-plan.md` |
| Plugin inventory | `docs/plugin-inventory.md` |

## Related Documentation

- `docs/plugin-inventory.md` - Plugin descriptions and comparison
- `utils/learning-tests/openai-vs-anthropic-protocol.md` - Protocol differences
- `utils/learning-tests/openai-streaming-schema.md` - Streaming behavior analysis
- `utils/learning-tests/openai-models-schema.md` - /models response format
