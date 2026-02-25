# ADR-004: Portal Route Structure

**Status:** Accepted
**Date:** 2026-02-25

## Context

Portal access requires 3 separate routes:
- `root-redirect-route` (`/`) → redirects to `/portal/`
- `portal-redirect-route` (`/portal`) → redirects to `/portal/`
- `oidc-generic-route` (`/portal/`, `/portal/*`) → OIDC auth + upstream

Question raised: why 3 routes instead of 1?

## Decision

Keep 3 separate routes. Each has single responsibility:

1. **Root redirect** - UX convenience for users hitting gateway root
2. **Trailing slash normalization** - `/portal` → `/portal/` without auth overhead
3. **Portal with OIDC** - actual authenticated portal access

## Consequences

**Easier:**
- Each route is simple and readable
- Redirect routes avoid unnecessary OIDC round-trips
- Clear separation of concerns

**Harder:**
- More files to manage (minor)
- Must understand pattern to avoid "simplifying" into single route

## Alternatives Considered

**Merge redirect into OIDC route:** Add `/portal` to uris array in `oidc-generic-route`. Rejected because every `/portal` request would trigger OIDC before redirecting - unnecessary latency and auth overhead for simple URL normalization.

**Remove root redirect:** Viable if root access not needed. Kept for UX - users expect gateway root to lead somewhere useful.

**APISIX trailing-slash plugin:** No built-in solution; would require custom Lua. Current redirect approach is simpler.
