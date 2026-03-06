# LLM API Gateway

Apache APISIX-based gateway for LLM providers (OpenAI, Anthropic) with auth, rate limiting, and usage tracking.

## Quick Start

```bash
# Start gateway
./infra/ctl/ctl.sh dev

# Verify
curl -sI localhost:9080/health | grep X-Gateway-Revision
```

## Endpoints

| Path | Description |
|------|-------------|
| `/llm/openai/v1/*` | OpenAI-compatible, routes by model name |
| `/llm/anthropic/v1/*` | Native Anthropic for Claude Code |
| `/health` | Health check |
| `/portal` | Self-service key management |

## Project Structure

```
services/
├── apisix/           # Gateway (APISIX + etcd)
│   ├── routes/       # Route definitions
│   └── lua/          # Custom plugins
└── portal/           # Key management UI (Flask)

infra/
├── env/              # Environment files
└── ctl/              # ctl.sh (lifecycle), consumers.sh (admin)
```

## Commands

```bash
./infra/ctl/ctl.sh dev              # Build + start + bootstrap + verify
./infra/ctl/ctl.sh dev --no-cache   # Force rebuild (no layer cache)
./infra/ctl/ctl.sh up portal --build # Rebuild + start single service
./infra/ctl/ctl.sh rebuild portal   # --no-cache build + restart
./infra/ctl/ctl.sh down             # Stop
./infra/ctl/ctl.sh logs -f          # Follow logs
./infra/ctl/ctl.sh routes           # List routes

# Consumer management (standalone)
./infra/ctl/consumers.sh list                        # List all consumers
./infra/ctl/consumers.sh move <ids...> --to <group>  # Move by OID, email, or handle
                          [--file path] [--dry-run]  # Bulk from file, preview mode
```

## Setup

1. Copy `infra/env/.env.dev.example` to `infra/env/.env.dev`
2. Set `ADMIN_KEY` and provider API keys
3. Run `./infra/ctl/ctl.sh dev`

## Docs

- [User Guide](docs/USER_GUIDE.md) - API usage examples
- [Architecture](docs/gateway-architecture.md) - Design details
- [ADRs](docs/adr/) - Architectural decisions
