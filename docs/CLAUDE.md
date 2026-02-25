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
│       ├── auth-transform.lua
│       ├── billing-extractor.lua
│       ├── model-policy.lua
│       ├── openai-auth.lua
│       ├── provider-response-id.lua
│       └── response-wiretap.lua
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

- `services/apisix/lua/apisix/plugins/auth-transform.lua` - Bearer → X-Api-Key transformation
- `services/apisix/lua/apisix/plugins/model-policy.lua` - Model registry + per-group access control
- `services/apisix/lua/apisix/plugins/billing-extractor.lua` - SSE streaming parser, usage extraction
- `services/apisix/lua/apisix/plugins/provider-response-id.lua` - Extract provider response ID from stream
- `services/apisix/routes/llm-ai-proxy-chat-openai.json` - Example route with full plugin chain
- `services/portal/src/app.py` - Portal backend (Consumer/credential management)
- `services/apisix/scripts/bootstrap.sh` - Route/consumer-group loader
- `infra/ctl/ctl.sh` - Unified control script

## Further Reading

- `/docs/adr/` - Architectural Decision Records (read before making changes)
- `/docs/gateway-architecture.md` - Detailed architecture reference
- GitHub Issues: https://github.com/wikefjol/prod-gateway/issues

## Ports (Dev)

- 9080: Gateway (public)
- 9180: Admin API (localhost only)
- 3001: Portal (localhost only)

## Work Routine

### Picking up work
1. Check "Current focus" below for active work
2. Review issue dependencies (see Issue Dependencies section)
3. Read relevant ADRs in `/docs/adr/` if touching that area
4. If something looks unconventional, check for an ADR - if none exists, flag it

### During work
1. Update "Current focus" when starting an issue
2. Document decisions in issue comments as you go
3. For significant/architectural decisions: create ADR before implementing
4. Update "Last completed" when done

### Deviation check
If implementation deviates from common patterns (e.g., unusual folder structure, non-standard tooling, custom solution over established library), an ADR MUST exist explaining why. No ADR = assume drift, discuss before proceeding.

## Current Focus
- **Active:** (none)
- **Last completed:** #46 portal route review → ADR-004 (Feb 2025)

## Issue Dependencies (Feb 2025)

```
#41 Entra app ──► #40 OpenWebUI install ──► #42 Workspace explore

#43 Consumer group matrix ─┬─► #44 Promotion script
                           └─► #45 Privilege scripts

#38 Firewall audit ──► #39 SWAG migration (informs urgency)
```

**No blockers:** #37, #38, #41, #47, #48
