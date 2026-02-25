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
| `/llm/ai-proxy/v1/*` | OpenAI-compatible, routes by model name |
| `/llm/claude-code/v1/*` | Native Anthropic for Claude Code |
| `/health` | Health check |
| `/portal` | Self-service key management |

## Project Structure

```
services/
├── apisix/           # Gateway (APISIX + etcd)
│   ├── routes/       # Route definitions
│   └── lua/          # Custom plugins
├── portal/           # Key management UI (Flask)
└── litellm/          # Placeholder (archived)

infra/
├── env/              # Environment files
└── ctl/ctl.sh        # Control script
```

## Commands

```bash
./infra/ctl/ctl.sh dev           # Build + start + bootstrap
./infra/ctl/ctl.sh dev --no-cache # Force rebuild
./infra/ctl/ctl.sh down          # Stop
./infra/ctl/ctl.sh logs -f       # Follow logs
./infra/ctl/ctl.sh routes        # List routes
```

## Setup

1. Copy `infra/env/.env.dev.example` to `infra/env/.env.dev`
2. Set `ADMIN_KEY` and provider API keys
3. Run `./infra/ctl/ctl.sh dev`

## Docs

- [User Guide](docs/USER_GUIDE.md) - API usage examples
- [Architecture](docs/gateway-architecture.md) - Design details
- [ADRs](docs/adr/) - Architectural decisions
