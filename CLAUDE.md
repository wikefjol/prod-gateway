# APISIX Gateway
LLM API gateway (Apache APISIX) — auth, rate-limiting, billing, self-service portal.

## Commands
```
./infra/ctl/ctl.sh dev              # build + start + bootstrap + verify
./infra/ctl/ctl.sh up [svc]         # start (no build, uses cached image)
./infra/ctl/ctl.sh up [svc] --build # start + rebuild (cached layers)
./infra/ctl/ctl.sh up --clean       # fresh etcd state (prompts DELETE)
./infra/ctl/ctl.sh down [--clean]   # stop [+ remove volumes]
./infra/ctl/ctl.sh rebuild [svc]    # --no-cache build + restart
./infra/ctl/ctl.sh bootstrap [--clean]
./infra/ctl/ctl.sh logs -f | routes | shell
```
Add `--test`/`-t` for test env (ports 9081/9181).

## Architecture
Repo: wikefjol/prod-gateway
Stack: Apache APISIX + Lua plugins, Flask portal, SWAG reverse proxy, Docker Compose, external CORE_NET
```
services/
├── apisix/   # gateway, config, routes, Lua plugins
├── portal/   # Flask self-service key management
└── swag/     # SWAG reverse proxy (nginx + certbot), TLS termination
infra/
├── env/      # .env.dev, .env.test
└── ctl/      # ctl.sh
docs/         # ADRs, architecture, user guide, diagrams
```
Request flow: Client → SWAG (TLS) → APISIX (auth-transform → openai-auth → model-policy → ai-proxy → provider-response-id → file-logger) → Upstream
Dev ports: 9080 gateway · 9180 admin · 3001 portal

## Code Style
- Lua plugins: header comment block required (purpose/phase/schema)
- Route config: JSON files only — no inline prose
- One fact, one place: model lists in MODEL_REGISTRY only; plugin docs in Lua headers only

## Workflow

1. **Issue first**: If no issue exists for the work, create one before coding
2. **Branch from issue**: Create `issue-<number>-<description>` branch
3. **Plan mode**: Review requirements, then implement
4. **Test**: Run tests before committing
5. **Routes/plugins change** → update docs per docs/adr/005-documentation-strategy.md
6. **Commit**: Use conventional commits (feat/fix/docs/test/refactor)
7. **PR**: Merge back to `master` after completion


## Testing
- `tests/`: gateway test suite — see [tests/README.md](tests/README.md) for setup, markers, structure
- `billing-tests/`: legacy pytest for billing/SSE parsing (separate venv, remote BASE_URL)
- **IMPORTANT**: API routes are `/llm/ai-proxy/v1/...`, NOT `/v1/...`

## Boundaries
YOU MUST NOT restate facts already in Lua headers, JSON routes, or MODEL_REGISTRY
IMPORTANT: Read relevant ADRs before modifying plugins, routes, or portal
YOU MUST NOT proceed without an ADR when implementation deviates from established patterns

## Context Pointers
- Setup/env: docs/setup.md
- Architecture detail: docs/gateway-architecture.md
- ADR index: docs/adr/INDEX.md
- Documentation policy: docs/adr/005-documentation-strategy.md
- User guide: docs/USER_GUIDE.md
- Diagrams: docs/diagrams/

## Current Focus
- Active: #61 CI/CD pipeline setup, #39 SWAG migration
- Last completed: #60 gateway test suite (Mar 2026)

## Gotchas
- ADMIN_KEY must be set before any ctl command (export or infra/env/.env.local)
- stream-usage-injector.lua is INACTIVE (not loaded in config.yaml)
- SWAG reverse proxy in `services/swag/` replaces former Apache2 (ADR-008); only container exposing 80/443
- After `dev`, verify X-Gateway-Revision == git rev-parse --short HEAD
