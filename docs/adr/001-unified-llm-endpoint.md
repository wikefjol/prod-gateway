# ADR-001: Unified LLM Endpoint with Model-Based Routing

**Status:** Accepted
**Date:** 2025-02-25

## Context

We need to expose multiple LLM providers (OpenAI, Anthropic) to clients. Clients include OpenWebUI and other tools that expect the OpenAI-compatible API interface (`/v1/chat/completions`, `/v1/models`).

Two approaches exist:
1. **Separate endpoints per provider:** `/llm/openai/v1/*`, `/llm/anthropic/v1/*`
2. **Unified endpoint:** `/llm/openai/v1/*` with routing based on model name in request body

## Decision

Use a unified endpoint with `post_arg.model` routing.

- Single endpoint: `/llm/openai/v1/chat/completions`
- Single models list: `/llm/openai/v1/models`
- APISIX routes based on `post_arg.model` regex matching:
  - `^(gpt|o1|o3|davinci|text-embedding)` → OpenAI upstream
  - `^claude` → Anthropic upstream (via ai-proxy translation)

Implementation: `services/apisix/routes/llm-openai-chat-*.json` using `vars` conditions.

## Consequences

**Easier:**
- Clients don't need to know which provider serves which model
- Model switching is transparent (change `model` field, same endpoint)
- OpenWebUI works out-of-the-box (expects single OpenAI-compatible endpoint)
- Adding new providers requires only new route + regex, no client changes

**Harder:**
- Route debugging slightly more complex (must check which route matched)
- Requires APISIX 3.14+ for `post_arg.*` support
- Unknown models need explicit rejection (handled by model-policy plugin)

## Alternatives Considered

**Separate endpoints per provider:**
- Rejected: Forces clients to know provider-model mapping
- Rejected: OpenWebUI would need custom configuration per provider
- Rejected: Model migrations (e.g., switching from GPT to Claude) require client changes

## Path Rename (2026-03)

Original path `/llm/ai-proxy/v1/*` leaked the APISIX plugin name. Renamed to protocol-based:

- `/llm/openai/v1/*` — OpenAI-compatible protocol (all models, regardless of upstream provider)
- `/llm/anthropic/v1/*` — native Anthropic protocol (Messages API)

This is **not** the rejected "separate endpoints per provider" — the OpenAI-protocol endpoint still routes to multiple providers (OpenAI, Anthropic, vLLM) based on `post_arg.model`. The `/llm/anthropic/` path exists only for clients that need the native Anthropic protocol (e.g., Claude Code).

Similarly, `llm-claude-code-*` route files renamed to `llm-anthropic-*` to describe the protocol, not the client.
