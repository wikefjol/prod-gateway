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

## Bootstrap Mechanism

`services/apisix/scripts/bootstrap.sh`:
- Reads all JSON files in `routes/`, `consumer-groups/`, `plugin-metadata/`
- Runs `envsubst` to substitute env vars
- PUTs each to APISIX Admin API (`http://localhost:${APISIX_ADMIN_PORT}/apisix/admin/...`)
- `--clean` flag: DELETEs all existing routes/consumers before loading

## Host

**Production:** Lamassu

**Apache2 reverse proxy** (system-level, outside repo):
`/etc/apache2/sites-available/ai-gateway-portal-chalmers.conf`

## Local vLLM Endpoints

- `alvis-worker1.c3se.chalmers.se`
- `alvis-worker2.c3se.chalmers.se`

Contact: Mikael Öhman (see email thread for access details and endpoint paths).
