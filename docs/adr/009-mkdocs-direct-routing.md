# ADR-009: MkDocs Docs Site via APISIX

**Status:** Accepted
**Date:** 2026-03-05

## Context

200-300 students onboarding soon. Documentation lives in `docs/USER_GUIDE.md` — not searchable, not navigable, not linkable from the portal. Need a proper docs site before launch.

Options for serving docs:
1. Route through APISIX with OIDC (like portal) — same auth session, simpler routing
2. Route directly via SWAG — separate nginx location, bypasses APISIX, public access

## Decision

Serve MkDocs Material at `/docs/` through APISIX with OIDC, same as the portal.

- **New service:** `services/docs/` — MkDocs Material in a Docker container (`mkdocs serve`)
- **Routing:** APISIX route `docs-route.json` with `openid-connect` plugin, upstream to docs container
- **Networking:** Docs container joins `CORE_NET` (same as portal)
- **Authentication:** Reuses the same OIDC session — students who hit `/portal/` are already authenticated for `/docs/`

Initially considered SWAG direct routing (bypassing APISIX), but reverted because:
- `/docs/` returned 404 from APISIX when SWAG didn't intercept it — confusing
- All other user-facing paths go through APISIX + OIDC; docs being different adds complexity
- One OIDC session covers portal + docs seamlessly
- No need for separate SWAG location blocks or dual-network container setup

## Consequences

**Easier:**
- Same routing pattern as portal — no special cases
- Docs container on single network (`CORE_NET`), like portal
- OIDC session shared with portal — no extra login
- No SWAG config changes needed

**Harder:**
- Docs require SSO login (acceptable — students already sign in for portal)
- `use_directory_urls` + `/docs/` prefix requires `site_url` config for correct internal links

## Alternatives Considered

**SWAG direct routing (tried, reverted):** Simpler in theory but created a routing split — some paths via SWAG, others via APISIX. Led to 404s and required docs container on both Docker networks.

**GitHub Pages / external hosting:** Content leaves the repo's deploy pipeline. Can't link bidirectionally with portal.
