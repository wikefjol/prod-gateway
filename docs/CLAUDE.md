# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LLM API Gateway built on Apache APISIX. Proxies requests to Anthropic, OpenAI, and LiteLLM with:
- Per-consumer API key auth (key-auth plugin + Bearer token transformation)
- Rate limiting (per-route burst + per-consumer-group quotas)
- Billing data extraction (custom billing-extractor Lua plugin → kafka-logger)
- Self-service key management portal (Flask)

## Development Commands

```bash
# RECOMMENDED: Build + start + bootstrap + verify revision
./infra/ctl/ctl.sh dev

# Fresh etcd state (removes volume, requires typing DELETE)
./infra/ctl/ctl.sh up --clean

# Other commands
./infra/ctl/ctl.sh down              # Stop gateway
./infra/ctl/ctl.sh down --clean      # Stop + remove all volumes
./infra/ctl/ctl.sh logs -f           # Follow logs
./infra/ctl/ctl.sh routes            # List routes from Admin API
./infra/ctl/ctl.sh bootstrap         # Load routes (additive)
./infra/ctl/ctl.sh bootstrap --clean # Delete all routes first, then load
./infra/ctl/ctl.sh shell             # Shell into apisix container
```

Test environment: add `--test` or `-t` flag (ports 9081/9181).

**Revision proof:** After `dev`, verify `X-Gateway-Revision` header matches `git rev-parse --short HEAD`:
```bash
curl -sI http://localhost:9080/health | grep X-Gateway-Revision
```

## Architecture

```
services/
├── apisix/
│   ├── compose.yaml      # includes etcd service
│   ├── Dockerfile
│   ├── config.yaml
│   ├── entrypoint-simple.sh
│   ├── routes/*.json
│   ├── consumer-groups/*.json
│   ├── plugin-metadata/*.json
│   ├── scripts/bootstrap.sh
│   └── lua/apisix/plugins/
│       ├── billing-extractor.lua
│       └── auth-transform.lua
├── portal/
│   ├── compose.yaml
│   ├── Dockerfile
│   ├── src/app.py
│   └── templates/
├── litellm/     # placeholder
└── openwebui/   # placeholder

infra/
├── env/
│   ├── .env.dev
│   └── .env.test
└── ctl/
    └── ctl.sh

utils/
└── billing-test.sh
```

**Network:** All services use external network `${CORE_NET}` (apisix-dev or apisix-test).

**Request flow:** Client → Apache2 → APISIX (auth-transform → key-auth → proxy-rewrite → billing-extractor → kafka-logger) → Upstream

**Apache reverse proxy:** `/etc/apache2/sites-available/ai-gateway-portal-chalmers.conf` (system-level, outside repo)

**Host:** Lamassu (production machine)

**Local vLLM:** `alvis-worker1.c3se.chalmers.se`, `alvis-worker2.c3se.chalmers.se` (see email from Mikael Öhman for details)

**Config loading:** `bootstrap.sh` PUTs consumer-groups, plugin-metadata, routes to APISIX Admin API using envsubst.

## Environment Files

`infra/env/.env.dev` / `.env.test` contain:
- CORE_NET, ENVIRONMENT
- **ADMIN_KEY** (required - must be set in environment or .env.local)
- VIEWER_KEY (defaults to ADMIN_KEY)
- OIDC vars
- Provider API keys (ANTHROPIC_API_KEY, OPENAI_API_KEY, LITELLM_KEY)
- Port overrides (APISIX_GATEWAY_PORT, APISIX_ADMIN_PORT, PORTAL_PORT)

**Setup:** Export `ADMIN_KEY` before running ctl commands, or create `.env.local` with `export ADMIN_KEY=<your-key>`.

## Key Files

- `services/apisix/lua/apisix/plugins/billing-extractor.lua` - SSE streaming parser, usage extraction
- `services/apisix/routes/llm-claude-code-messages.json` - Example route with full plugin chain
- `services/portal/src/app.py` - Portal backend (Consumer/credential management)
- `services/apisix/scripts/bootstrap.sh` - Route/consumer-group loader
- `infra/ctl/ctl.sh` - Unified control script

## Ports (Dev)

- 9080: Gateway (public)
- 9180: Admin API (localhost only)
- 3001: Portal (localhost only)
