# ADR-006: vLLM Multi-Port Routing Strategy

**Status:** Accepted
**Date:** 2026-03-03

## Context

Alvis HPC (C3SE) serves 4 vLLM models on separate ports (one vLLM process per model for GPU isolation). Each model has a distinct `host:port` endpoint. Unlike OpenAI/Anthropic where one provider URL serves all models, each vLLM model requires a different upstream.

APISIX's `ai-proxy` plugin binds provider config (endpoint, auth) at route definition time — it cannot be overridden dynamically per-request. This means one route per distinct upstream endpoint.

Additionally, model names can collide with existing provider regexes (e.g. `gpt-oss-20b` matches the OpenAI regex `^(gpt|...)`), requiring priority-based disambiguation.

## Decision

**One route per vLLM model** with exact-match `vars` at **priority 11** (above commercial provider regex routes at priority 10).

Priority convention:
- **10:** Regex/prefix provider routes (OpenAI, Anthropic)
- **11:** Exact-match model routes (vLLM, other self-hosted)

Each route uses `ai-proxy` with `provider: "openai-compatible"`, a hardcoded `override.endpoint`, and `options.model` to remap the gateway alias to the HuggingFace model name.

## Consequences

**Easier:**
- Simple, explicit — each route is self-contained
- No new infrastructure or services
- No additional latency hops
- Exact matches are inherently more specific; higher priority is natural

**Harder:**
- One route file per model when models are on separate ports
- Priority convention must be followed; undocumented, it's a footgun
- Scaling concern: 40 models on 40 ports = 40 route files

## Alternatives Considered

### A. Local reverse proxy (nginx/Flask on lamassu)

Consolidate all vLLM ports behind a single local endpoint (e.g. `localhost:9090`). Proxy reads model name from request body, fans out to the correct Alvis port. APISIX sees one endpoint → one route.

- **Pro:** APISIX stays clean — one route, one regex, same pattern as OpenAI/Anthropic
- **Con:** Extra service to run/monitor, additional latency hop (matters for streaming), another failure point
- **Verdict:** Over-engineering for 4 models. Revisit if model count exceeds ~10 on distinct ports.

### B. Upstream consolidation at C3SE

Ask C3SE to put a reverse proxy (nginx) or load balancer in front of the vLLM instances, exposing one port. vLLM already supports multi-model serving; even with separate processes, a proxy on their side is natural.

- **Pro:** Cleanest solution — eliminates the problem at the source
- **Con:** Depends on C3SE infrastructure decisions outside our control
- **Verdict:** Recommended if C3SE is willing. Communicate that single-port exposure simplifies downstream integration.

### C. Custom Lua dispatcher (skip ai-proxy for vLLM)

Single catch-all route with a custom plugin that reads model from body, looks up endpoint in a Lua table, sets upstream dynamically via `proxy-rewrite`.

- **Pro:** One route for all vLLM models regardless of port count
- **Con:** Reimplements upstream dispatch that ai-proxy provides; loses ai-proxy's protocol translation, logging integration, and `options.model` remapping
- **Verdict:** High effort, low payoff. Only justified if we outgrow ai-proxy entirely.

### D. Tighten OpenAI regex to exclude collisions

Change OpenAI regex from `^(gpt|o1|o3|...)` to `^(gpt-[34]|gpt-4o|o1|o3|...)` so `gpt-oss-20b` doesn't match.

- **Pro:** No priority changes needed
- **Con:** Fragile — couples route regexes to specific model names, breaks on new models like `gpt-5`
- **Verdict:** Rejected. Priority-based resolution is more robust.

## Future Trigger

If the number of vLLM models on distinct ports exceeds ~10, revisit options A or B. The current approach is appropriate for the 4-model deployment.
