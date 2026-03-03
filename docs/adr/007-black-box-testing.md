# ADR-007: Black-Box Testing with Characterization Fixtures

**Status:** Accepted
**Date:** 2026-03-03

## Context

No gateway-internal test suite exists. `billing-tests/` covers billing-specific logic but uses a remote BASE_URL and separate structure. An external client-side suite (`docs/incoming/TEST_SUITE_OVERVIEW.md`) validates OpenAI SDK compatibility and performance but runs outside the infrastructure and makes real provider API calls.

We need tests that cover gateway routing, auth, access control, and error formats — without depending on upstream provider availability or costing money per run.

## Decision

### Black-box characterization testing

Tests treat the gateway as a black box over HTTP. No Lua unit tests, no APISIX internals mocking. This matches how clients actually use the gateway.

**Characterization approach**: capture real gateway responses as JSON fixtures, then write tests that assert against those fixtures. This inverts the usual TDD flow — instead of specifying behavior upfront, we record actual behavior and lock it down.

### Capture-then-test workflow

1. `tests/capture/record.py` probes a live dev gateway and writes JSON to `tests/fixtures/`
2. Fixtures are committed to git (baseline for CI, reviewable in PRs)
3. Tests load fixtures via `load_fixture()` and assert structure/status/fields
4. Re-capture when gateway behavior intentionally changes (new routes, new models, policy changes)

### Fixture format

```json
{
  "captured_at": "ISO-8601",
  "gateway_revision": "short SHA",
  "request": { "method": "...", "path": "...", "body": ... },
  "response": { "status": 200, "headers": {...}, "body": {...} }
}
```

`access_matrix.json` is special: records only status codes per (tier, model) pair, not full response bodies.

### Test tiers (pytest markers)

- `smoke` — fast, offline, fixture-based (route structure, error shapes, access matrix)
- `live` — requires running gateway (real HTTP calls to localhost:9080)
- `vllm` — requires Alvis backends (may be down)

### Framework

pytest + httpx + OpenAI SDK. Deterministic test consumer keys from `services/apisix/test-consumers/`. Separate from `billing-tests/`.

## Consequences

**Easier:**
- Fast CI feedback — smoke tests run against fixtures, no gateway needed
- Regression detection — committed fixtures make behavioral changes visible in diffs
- No upstream costs — fixture-based tests never hit OpenAI/Anthropic
- Low barrier — capture script auto-generates the baseline

**Harder:**
- Fixtures go stale — must re-capture after intentional changes
- No internal coverage — can't test Lua plugin logic in isolation
- Doesn't replace the client-side perf suite — that remains separate for latency benchmarks

## Alternatives Considered

**Lua unit tests (busted/luaunit):** Would test plugin logic directly but requires mocking APISIX internals (`core.request`, `core.response`). High coupling to APISIX API surface. Doesn't test the assembled pipeline. May add later as complement.

**Mock provider responses:** Would enable fully offline live tests. Adds complexity (mock server, response fixtures for each provider). Not needed yet — smoke tests cover most regression risk. Can layer in later.

**Adapt client-side suite directly:** The external suite (`TEST_SUITE_OVERVIEW.md`) uses a multi-target baseline comparison pattern with real API calls. Valuable for perf benchmarks but too slow/expensive for routine CI. We borrow its test cases and error format expectations, not its execution model.

**This ADR may be superseded** by a broader test strategy ADR once testing is no longer backlogged.
