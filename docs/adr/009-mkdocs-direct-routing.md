# ADR-009: MkDocs Direct Routing via SWAG

**Status:** Accepted
**Date:** 2026-03-05

## Context

200-300 students onboarding soon. Documentation lives in `docs/USER_GUIDE.md` — not searchable, not navigable, not linkable from the portal. Need a proper docs site before launch.

Options for serving docs:
1. Route through APISIX (like portal) — adds auth overhead, OIDC redirects for public content
2. Route directly via SWAG — simple nginx proxy, no auth, public content

## Decision

Serve MkDocs Material at `/docs/` via SWAG directly, bypassing APISIX entirely.

- **New service:** `services/docs/` — MkDocs Material in a Docker container (`mkdocs serve`)
- **Routing:** SWAG `location /docs/` block in both subdomain configs, before `location /`
- **Networking:** Docs container joins both `apisix-dev` and `apisix-test` networks with alias `docs`
- **No authentication:** Documentation is public content, no OIDC/key-auth needed

## Consequences

**Easier:**
- Docs are accessible without SSO login
- No APISIX route/plugin configuration needed
- MkDocs Material provides search, navigation, mobile support out of the box
- Content is versioned in-repo as Markdown

**Harder:**
- Docs container must join both Docker networks (same pattern as SWAG itself)
- `use_directory_urls` + `/docs/` prefix requires `site_url` config for correct internal links
- Adding a new service to manage (lightweight — single Python process)

## Alternatives Considered

**Route through APISIX:** Unnecessary complexity. Docs are public, don't need auth or rate limiting. Would require an APISIX route + upstream config for no benefit.

**Static files on SWAG:** Could build MkDocs and serve static files from SWAG volume. Loses live reload in dev and requires a build step. MkDocs serve is simple enough.

**GitHub Pages / external hosting:** Content leaves the repo's deploy pipeline. Can't link bidirectionally with portal. Students need VPN or Chalmers network for other services anyway.
