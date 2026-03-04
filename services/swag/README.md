# SWAG Reverse Proxy

SWAG (linuxserver nginx + certbot) terminates TLS and routes by domain to backend services. See [ADR-008](../../docs/adr/008-swag-reverse-proxy.md).

## Domains

| Domain | Backend | Status |
|--------|---------|--------|
| `lamassu.ita.chalmers.se` | dev APISIX (`apisix-dev:9080`) | Active |
| `ai-gateway.portal.chalmers.se` | test APISIX (`apisix-test:9080`) | Active |
| `openwebui.portal.chalmers.se` | OpenWebUI | Stubbed (rename `.sample` -> `.conf` for #40) |

## Adding a New Domain

1. Create `nginx/site-confs/<name>.subdomain.conf`
2. Add domain to `EXTRA_DOMAINS` in `compose.yaml`
3. Restart SWAG: `./infra/ctl/ctl.sh down swag && ./infra/ctl/ctl.sh up swag`
