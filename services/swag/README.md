# SWAG Reverse Proxy

SWAG (linuxserver nginx + certbot) terminates TLS and routes by domain to backend services. See [ADR-008](../../docs/adr/008-swag-reverse-proxy.md).

## Domains

| Domain | Backend | Status |
|--------|---------|--------|
| `lamassu.ita.chalmers.se` | dev APISIX (`apisix-dev:9080`) | Active |
| `ai-gateway.portal.chalmers.se` | test APISIX (`apisix-test:9080`) | Active |
| `openwebui.portal.chalmers.se` | OpenWebUI | Stubbed (rename `.sample` -> `.conf` for #40) |

## Cutover Runbook

Apache2 holds 80/443 — brief downtime is unavoidable with HTTP validation.

### Steps

1. **Stop Apache2:**
   ```bash
   sudo systemctl stop apache2
   ```

2. **Start SWAG with staging certs** (test without rate-limit risk):
   ```bash
   SWAG_STAGING=true ./infra/ctl/ctl.sh up swag
   ```

3. **Verify staging certs:**
   ```bash
   curl -kI https://lamassu.ita.chalmers.se
   curl -kI https://ai-gateway.portal.chalmers.se
   ```

4. **Switch to production certs:**
   ```bash
   ./infra/ctl/ctl.sh down swag
   # Remove SWAG_STAGING or set to false
   ./infra/ctl/ctl.sh up swag
   ```

5. **Verify production:**
   ```bash
   curl -I https://lamassu.ita.chalmers.se
   curl -I https://ai-gateway.portal.chalmers.se
   ```

6. **Disable Apache2:**
   ```bash
   sudo systemctl disable apache2
   ```

### Rollback

```bash
./infra/ctl/ctl.sh down swag
sudo systemctl start apache2
```

## Adding a New Domain

1. Create `nginx/proxy-confs/<name>.subdomain.conf`
2. Add domain to `EXTRA_DOMAINS` in `compose.yaml`
3. Restart SWAG: `./infra/ctl/ctl.sh down swag && ./infra/ctl/ctl.sh up swag`
