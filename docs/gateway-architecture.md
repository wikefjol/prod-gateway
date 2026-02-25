# APISIX Gateway Architecture Reference

Architecture reference for the LLM API Gateway. See `docs/diagrams/` for visual flows.

## Routing Paths

| Path | Route | Key Plugins | Upstream |
|------|-------|-------------|----------|
| `/llm/ai-proxy/v1/*` | ai-proxy | auth-transform → openai-auth → model-policy → ai-proxy → provider-response-id | OpenAI / Anthropic (model-based) |
| `/llm/claude-code/v1/*` | claude-code | auth-transform → key-auth → consumer-restriction → billing-extractor | Anthropic direct |

## Auth Flow

1. `auth-transform` (priority 12020, rewrite phase) — converts `Authorization: Bearer <token>` → `X-Api-Key: <token>`, sanitizes request IDs
2. `openai-auth` / `key-auth` (priority 2500) — looks up consumer by key, attaches consumer context; openai-auth returns OpenAI-format 401s
3. Consumer context (`consumer_name`, `consumer_group_id`) available to all downstream plugins

`auth-transform` is a registered plugin (config.yaml), invoked directly in route plugin config — not via serverless-pre-function.

## Consumer Groups

Two groups with weekly rate limiting via `limit-count`:

| Group ID | Weekly Quota | Access |
|----------|--------------|--------|
| `base_user` | 1,000,000 | Mini models only |
| `premium_user` | 1,000,000 | All models |
| `claude_code_users` | 1,000,000 | All models + claude-code sidecar |

Consumers linked to group via `group_id` field at creation. Rate limit key: `consumer_name`.

Files: `services/apisix/consumer-groups/*.json`

## Provider Routing (ai-proxy)

Routes share the same URI but use `vars` with `post_arg.model` regex to select provider:

```
POST /llm/ai-proxy/v1/chat/completions {"model": "gpt-4o-mini"}
  → vars: [["post_arg.model", "~~", "^(gpt|o1|o3|davinci|text-embedding)"]] → OpenAI

POST /llm/ai-proxy/v1/chat/completions {"model": "claude-haiku-4-5"}
  → vars: [["post_arg.model", "~~", "^claude"]] → Anthropic
```

`post_arg.*` support requires APISIX 3.14+ (current: 3.15.0-debian). Unknown models rejected by `model-policy` with 400.

Model registry lives in `model-policy.lua` MODEL_REGISTRY — single source of truth.

## ai-proxy Protocol Translation

The `ai-proxy` plugin handles OpenAI↔Anthropic format translation:

| Direction | What happens |
|-----------|--------------|
| Request → Anthropic | Converts OpenAI `messages` format to Anthropic format |
| Response ← Anthropic | Converts Anthropic response to OpenAI `choices` format |
| Streaming ← Anthropic | Converts Anthropic SSE events to OpenAI SSE chunk format |

Clients always send/receive OpenAI-format regardless of backend provider.

## Upstream Config & Key Injection

Upstreams are defined per-route in `ai-proxy` plugin config (no shared upstream objects). API keys injected at bootstrap time via `envsubst`:

1. Keys in `infra/env/.env.dev`: `ANTHROPIC_API_KEY=...`, `OPENAI_API_KEY=...`
2. `bootstrap.sh` runs `envsubst < route.json` before PUT to Admin API
3. Route JSON uses `$VAR` syntax: `"Authorization": "Bearer $OPENAI_API_KEY"`
4. Actual keys stored in etcd after bootstrap, not in container filesystem

## Billing Log Schema

All paths log to `logs/billing/*.log` via `file-logger`:

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

## Streaming Verification

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
  -d '{"model":"claude-haiku-4-5","messages":[{"role":"user","content":"count 1 to 5"}],"stream":true}'
```

Expected: SSE stream with `data: {...}` chunks ending with `data: [DONE]`.
