# Setup & Environment

## ADMIN_KEY

Required before any `ctl.sh` command. Two options:

1. Export in shell: `export ADMIN_KEY=<your-key>`
2. Create `infra/env/.env.local` with: `export ADMIN_KEY=<your-key>`

`ctl.sh` sources `.env.local` if it exists.

## Environment Files

`infra/env/.env.dev` and `infra/env/.env.test` — values sourced by `ctl.sh`:

| Variable | Description |
|---|---|
| `CORE_NET` | External Docker network (`apisix-dev` or `apisix-test`) |
| `ENVIRONMENT` | `dev` or `test` |
| `ADMIN_KEY` | APISIX Admin API key (must be set; see above) |
| `VIEWER_KEY` | Read-only Admin API key (defaults to ADMIN_KEY) |
| `OIDC_*` | OIDC configuration for portal auth |
| `ANTHROPIC_API_KEY` | Anthropic upstream key |
| `OPENAI_API_KEY` | OpenAI upstream key |
| `APISIX_GATEWAY_PORT` | Override gateway port (default 9080 / 9081 test) |
| `APISIX_ADMIN_PORT` | Override admin port (default 9180 / 9181 test) |
| `PORTAL_PORT` | Override portal port (default 3001) |
| `SWAG_EMAIL` | Let's Encrypt notification email (SWAG) |

## Bootstrap Mechanism

`services/apisix/scripts/bootstrap.sh`:
- Reads all JSON files in `routes/`, `consumer-groups/`, `plugin-metadata/`
- Runs `envsubst` to substitute env vars
- PUTs each to APISIX Admin API (`http://localhost:${APISIX_ADMIN_PORT}/apisix/admin/...`)
- `--clean` flag: DELETEs all existing routes/consumers before loading

## Host

**Production:** Lamassu

### SWAG Reverse Proxy

SWAG handles TLS termination and domain routing. Config in `services/swag/`.

```bash
# Start SWAG (requires ports 80/443 free)
./infra/ctl/ctl.sh up swag

# Or include in dev workflow
./infra/ctl/ctl.sh dev --with-swag
```

Set `SWAG_EMAIL` in `infra/env/.env.dev` for Let's Encrypt notifications.

First run: set `SWAG_STAGING=true` to test with staging certs. See [services/swag/README.md](../services/swag/README.md) for full cutover runbook.

**Note:** Former Apache2 reverse proxy (`/etc/apache2/sites-available/`) replaced by SWAG (ADR-008).

## Alvis vLLM Endpoints (C3SE HPC)

Hardcoded in route JSON files (no env vars needed — same VLAN, no auth):

| Model | Endpoint |
|-------|----------|
| qwen3-coder-30b | `http://alvis-worker1.c3se.chalmers.se:43181/v1/chat/completions` |
| gemma-3-12b-it | `http://alvis-worker1.c3se.chalmers.se:43111/v1/chat/completions` |
| gpt-oss-20b | `http://alvis-worker1.c3se.chalmers.se:43121/v1/chat/completions` |
| nomic-embed-text-v1.5 | `http://alvis-worker1.c3se.chalmers.se:43211/v1/embeddings` |

Gateway aliases are remapped to HuggingFace names via `ai-proxy` `options.model`.

Contact: Mikael Öhman (see email thread for access details and endpoint paths).
