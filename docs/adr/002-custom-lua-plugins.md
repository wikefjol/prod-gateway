# ADR-002: Custom Lua Plugins

**Status:** Accepted
**Date:** 2025-02-25

## Context

APISIX provides many built-in plugins, but our LLM gateway has specific requirements not fully covered by existing plugins. We need to decide when to build custom vs use built-in.

## Decision

Build custom Lua plugins for the following, with justification:

### auth-transform

**Purpose:** Transform `Authorization: Bearer <token>` to `X-Api-Key: <token>` before key-auth runs.

**Why custom:** No built-in APISIX plugin does this transformation. Feature request exists ([#12908](https://github.com/apache/apisix/issues/12908)) but not implemented as of Feb 2025. `proxy-rewrite` cannot conditionally transform headers based on content.

**File:** `services/apisix/lua/apisix/plugins/auth-transform.lua`

### model-policy

**Purpose:**
1. Enforce model access per consumer group (action=enforce)
2. Render `/v1/models` response filtered by consumer group privileges (action=render)

**Why custom:** Built-in `consumer-restriction` works on route/consumer level, not on request body content. We need per-model access control where the model is specified in the JSON body, and different consumer groups see/use different model subsets.

**File:** `services/apisix/lua/apisix/plugins/model-policy.lua`

### billing-extractor

**Purpose:** Parse SSE streaming responses to extract token usage for billing logs. Forces `stream_options.include_usage=true` if client didn't set it, ensuring consistent usage data in responses.

**Why custom:** While APISIX 3.12+ exposes `$llm_prompt_tokens` and `$llm_completion_tokens` via ai-proxy, we need:
- Guaranteed usage in SSE streams (inject stream_options if missing)
- Consistent client experience (usage always present)
- Custom billing variables for kafka-logger

**File:** `services/apisix/lua/apisix/plugins/billing-extractor.lua`

**Note:** Review overlap with built-in ai-proxy variables in future. May be partially redundant.

### provider-response-id

**Purpose:** Extract provider response ID from SSE stream for billing correlation.

**Why custom:** No built-in plugin extracts response IDs from streaming LLM responses. Needed for billing log enrichment and debugging.

**File:** `services/apisix/lua/apisix/plugins/provider-response-id.lua`

## Consequences

**Easier:**
- Full control over LLM-specific logic
- Can extend without waiting for upstream APISIX
- Single source of truth for model registry (in model-policy.lua)

**Harder:**
- Maintenance burden for custom plugins
- Must track APISIX updates that might obsolete custom code
- Testing requires understanding Lua/OpenResty

## Alternatives Considered

**Use only built-in plugins:**
- Rejected: key-auth doesn't support Bearer tokens natively
- Rejected: consumer-restriction can't filter by request body model field
- Rejected: No built-in usage extraction from SSE with injection capability
