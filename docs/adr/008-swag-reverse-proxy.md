# ADR-008: SWAG Reverse Proxy

**Status:** Accepted
**Date:** 2026-03-04

## Context

System-level Apache2 at `/etc/apache2/sites-available/` reverse-proxies two domains to APISIX. Config lives outside the repo, making it unversioned and unportable. A third domain (OpenWebUI, #40) is coming. Docker firewall concerns from #38 are resolved.

Current Apache vhosts:
- `lamassu.ita.chalmers.se` -> dev APISIX (`127.0.0.1:9080`)
- `ai-gateway.portal.chalmers.se` -> test APISIX (`127.0.0.1:9081`)

Both do: HTTP->HTTPS redirect, Let's Encrypt TLS, reverse proxy, websocket upgrade, admin API block, security headers (HSTS, nosniff, X-Frame, Referrer-Policy), X-Forwarded-* headers.

## Decision

Replace Apache2 with a single SWAG (linuxserver nginx + certbot) container that:

1. **Joins both Docker networks** (`apisix-dev` and `apisix-test`) to route by domain
2. **Routes by domain:**
   - `lamassu.ita.chalmers.se` -> `apisix-dev` (dev APISIX via network alias)
   - `ai-gateway.portal.chalmers.se` -> `apisix-test` (test APISIX via network alias)
   - `openwebui.portal.chalmers.se` -> OpenWebUI (stubbed, enabled with #40)
3. **Is the only container exposing 80/443** — all other services bind `127.0.0.1` only
4. **Lives in `services/swag/`** with compose.yaml and nginx confs checked into repo
5. **Uses HTTP validation** for Let's Encrypt (simplest, no DNS provider needed)

Network aliases (`apisix-dev`, `apisix-test`) added to each APISIX compose give SWAG stable DNS names, avoiding fragile auto-generated container names.

## Consequences

**Easier:**
- Reverse proxy config is versioned, reviewed, and portable
- Adding new domains is a PR (new proxy conf file)
- Cert renewal is automatic (SWAG built-in certbot)
- Docker-native networking replaces host-level `127.0.0.1` proxying

**Harder:**
- Brief downtime during cutover (Apache holds 80/443)
- SWAG container must join multiple Docker networks
- Operators must understand SWAG conventions (proxy-confs, site-confs)

## Alternatives Considered

**Traefik:** Auto-discovers Docker services via labels. More magic, harder to debug, label-based config doesn't version as cleanly as nginx confs.

**Caddy:** Elegant config syntax, automatic HTTPS. Less ecosystem support, fewer community examples for multi-network setups.

**Keep Apache2:** Works today but config lives outside repo. Adding OpenWebUI means a third unversioned vhost on the host.
