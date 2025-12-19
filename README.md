# APISIX Gateway with Multi-Provider OIDC Authentication

A production-ready, modular Infrastructure-as-Code (IaC) implementation of Apache APISIX Gateway with comprehensive multi-provider OIDC authentication support and AI provider proxying capabilities.

## 🚀 Features

- **Multi-Provider OIDC**: Support for Microsoft EntraID (Azure AD) and Keycloak
- **Self-Service Portal**: Python Flask backend for API key management
- **AI Provider Gateway**: Secure proxying to OpenAI, Anthropic, and LiteLLM endpoints
- **Multi-Environment Support**: Clean separation between dev, test, and production environments
- **Security Hardening**: Admin API localhost-only binding, TLS termination, and proper authentication flows
- **Clean Architecture**: Modular configuration with provider-specific separation of concerns
- **Infrastructure as Code**: Fully automated deployment with Docker Compose

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [System Requirements](#-system-requirements)
- [CLI Usage](#-cli-usage)
- [Architecture Overview](#-architecture-overview)
- [Configuration](#-configuration)
- [Usage Examples](#-usage-examples)
- [Security Features](#-security-features)
- [Troubleshooting](#-troubleshooting)
- [Documentation](#-documentation)
- [Contributing](#-contributing)

## ⚡ Quick Start

### Prerequisites

- Docker & Docker Compose
- Python 3.8+ (for CLI)
- curl (for testing)
- bash (scripts are bash-based)

### Using the CLI (Recommended)

The gateway includes a powerful CLI for easy management:

```bash
# Complete setup (one command - the "gold standard")
./gw reset dev

# Check system status
./gw status dev

# Run comprehensive health checks
./gw doctor dev

# View configured routes
./gw routes dev

# View all CLI commands
./gw --help
```

### Manual Setup (Advanced Users)

For manual control or troubleshooting:

```bash
# Start with Microsoft EntraID (recommended for production)
./scripts/lifecycle/start.sh --provider entraid

# Start with Keycloak (local development)
./scripts/lifecycle/start.sh --provider keycloak

# Start with debug tools
./scripts/lifecycle/start.sh --provider entraid --debug
```

### Test the Setup

```bash
# Check system health
curl http://localhost:9080/health

# Test the portal (triggers OIDC flow)
curl -I http://localhost:9080/portal/

# View available routes (manual method)
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes
```

### Stop the Environment

```bash
# Using CLI
./gw down dev

# Manual method
./scripts/lifecycle/stop.sh
```

## 🔧 System Requirements

### Minimum Requirements

- **OS**: Linux (Ubuntu 20.04+ recommended), macOS, or Windows with WSL2
- **Memory**: 4GB RAM minimum, 8GB+ recommended
- **Storage**: 2GB free space for Docker images
- **Docker**: Version 20.10+ with Docker Compose V2

### Port Usage

| Port | Service | Binding | Purpose |
|------|---------|---------|---------|
| 9080 | APISIX Gateway | 0.0.0.0 | Main API gateway |
| 9180 | APISIX Admin | 127.0.0.1 | Admin API (localhost-only for security) |
| 3001 | Portal Backend | 0.0.0.0 | Self-service API key management |
| 8080 | Keycloak | 0.0.0.0 | Local OIDC provider (when using keycloak) |
| 2379 | etcd | container-only | Configuration storage |

## 💻 CLI Usage

### Gateway CLI Commands

The CLI provides a unified interface for all gateway operations:

#### Core Operations
```bash
./gw up dev|test               # Start infrastructure
./gw down dev|test             # Stop environment
./gw reset dev|test            # Complete reset: down → up → bootstrap → verify
./gw bootstrap dev|test        # Deploy routes using proven bootstrap-core.sh
```

#### Diagnostics and Monitoring
```bash
./gw status [dev|test]         # Container status, service health, routes
./gw env dev|test              # Show environment configuration
./gw doctor dev|test           # Comprehensive health checks and diagnostics
./gw logs dev|test [service]   # View service logs with follow/tail options
./gw routes dev|test           # List and inspect configured APISIX routes
```

### CLI Examples

#### Complete Environment Reset
```bash
# Reset entire dev environment (the "gold standard" operation)
./gw reset dev

# Reset with volume cleanup
./gw reset dev --clean

# Include provider routes (requires AI API keys)
./gw reset dev --with-providers
```

#### Monitoring and Debugging
```bash
# Check overall system health
./gw doctor dev

# View detailed routes with upstreams and plugins
./gw routes dev --detailed

# Follow APISIX logs in real-time
./gw logs dev apisix --follow

# Check environment variables and configuration
./gw env dev
```

#### Step-by-Step Control
```bash
# Manual workflow
./gw down dev --clean
./gw up dev
./gw bootstrap dev --core-only
./gw status dev
```

### Safety Features

- **Explicit Environment Targeting**: Always specify `dev` or `test` - no dangerous defaults
- **Safe Cleanup**: Project-only cleanup by default with `--clean`
- **Global Cleanup Warning**: `--prune-global` requires explicit confirmation
- **Core vs Provider Routes**: `--core-only` (default) vs `--with-providers` for graceful API key handling

### Installation

The CLI uses a Python virtual environment with all dependencies managed automatically:

```bash
# CLI wrapper handles virtual environment activation
./gw --help

# Manual virtual environment setup (if needed)
python3 -m venv cli/venv
source cli/venv/bin/activate
pip install -r cli/requirements.txt
```

See [CLI_USAGE.md](CLI_USAGE.md) for complete documentation.

## 🏗️ Architecture Overview

### Core Components

```
Internet → Apache (443/80) → APISIX Gateway → Portal Backend → Services
                ↓
        OIDC Authentication:
        - Microsoft EntraID (Production)
        - Keycloak (Local Development)
```

### Service Architecture

- **APISIX Gateway**: Core API gateway with OIDC routing and AI provider proxying
- **Portal Backend**: Python Flask self-service API key management
- **etcd**: Configuration store for APISIX
- **Multi-Provider OIDC**: Switchable authentication backends

### Network Security Model

- **Public Access**: Gateway (9080) and Portal (3001) - OIDC protected
- **Internal Only**: Admin API (9180) - localhost binding for security
- **Container Network**: etcd (2379) - isolated within Docker network

## ⚙️ Configuration

### Environment Structure

The system uses hierarchical configuration loading:

```
config/
├── shared/           # Common APISIX settings
│   ├── base.env     # Core configuration
│   └── apisix.env   # APISIX admin keys
├── providers/       # Provider-specific configs
│   ├── entraid/     # Microsoft EntraID settings
│   └── keycloak/    # Keycloak settings
├── env/             # Environment-specific settings
│   ├── dev.env      # Development ports/settings
│   └── test.env     # Test environment settings
└── secrets/         # Credentials (gitignored)
    └── entraid-dev.env  # EntraID secrets
```

### Provider Configuration

#### Microsoft EntraID (Recommended)

1. Update your secrets file:
```bash
cp secrets/entraid-dev.env.example secrets/entraid-dev.env
# Edit with your actual EntraID credentials
```

2. Configure your EntraID app registration:
   - Redirect URI: `https://your-domain.com/portal/callback`
   - Required API permissions for user profile access

#### Keycloak (Local Development)

Keycloak runs automatically with default admin credentials (admin/admin) when using the keycloak provider.

## 📖 Usage Examples

### Portal Access (OIDC Authentication Required)

```bash
# Access portal (triggers OIDC authentication flow)
curl -I http://localhost:9080/portal/

# Generate API key (after OIDC login)
curl -X POST \
     -H "X-User-Oid: user-123" \
     http://localhost:9080/portal/get-key
```

### AI Provider API Usage (API Key Required)

```bash
# Anthropic Claude API
curl -X POST http://localhost:9080/v1/providers/anthropic/chat \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR-API-KEY" \
  -d '{
    "model": "claude-3-sonnet-20240229",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# OpenAI GPT API
curl -X POST http://localhost:9080/v1/providers/openai/chat \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR-API-KEY" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# LiteLLM (Local Models)
curl -X POST http://localhost:9080/v1/providers/litellm/chat \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR-API-KEY" \
  -d '{
    "model": "ollama/llama3.3",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## 🔒 Security Features

### Current Security Measures

- ✅ **Admin API Security**: Bound to localhost only (`127.0.0.1:9180`)
- ✅ **OIDC Authentication**: Full OpenID Connect flow for portal access
- ✅ **API Key Authentication**: Secure CSPRNG key generation for API access
- ✅ **Network Isolation**: Proper container networking and port binding
- ✅ **Secret Management**: Gitignored secrets with example templates
- ✅ **Header Security**: Proper OIDC header injection and validation

### Security Model

1. **Portal Access**: OIDC authentication required → Header injection → Portal backend
2. **API Usage**: API key validation → Provider-specific header injection → Upstream proxy
3. **Admin Access**: Localhost-only binding prevents external admin API access

### Production Security Checklist

- [ ] Update all placeholder secrets with production values
- [ ] Configure TLS termination (Apache/nginx reverse proxy)
- [ ] Set up proper DNS with valid SSL certificates
- [ ] Configure rate limiting for API endpoints
- [ ] Set up monitoring and alerting
- [ ] Regular security updates for container images

## 🐛 Troubleshooting

### CLI Troubleshooting (Recommended)

The CLI provides comprehensive diagnostics:

```bash
# Quick health check
./gw doctor dev

# Check system status
./gw status dev

# View environment configuration
./gw env dev

# Check logs for errors
./gw logs dev apisix --tail 50

# View route configuration
./gw routes dev --detailed
```

### Common Issues

#### Services Won't Start
```bash
# CLI approach (recommended)
./gw doctor dev           # Comprehensive diagnostics
./gw status dev          # Container and service status
./gw logs dev apisix     # View APISIX logs

# Manual approach
docker info              # Check Docker daemon
ss -lntp | grep ':908[01]'  # Check port conflicts
docker logs apisix-dev-apisix-1  # View startup logs
```

#### OIDC Authentication Fails
```bash
# CLI approach (recommended)
./gw env dev             # Check all OIDC configuration
./gw doctor dev          # Run authentication tests
./gw routes dev --route-id portal-oidc-route  # Check OIDC route

# Manual approach
curl $OIDC_DISCOVERY_ENDPOINT  # Test discovery endpoint
echo $OIDC_REDIRECT_URI        # Verify redirect URI
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes/portal-oidc-route
```

#### Environment Variables Missing
```bash
# CLI approach (recommended)
./gw env dev             # Show all environment variables and sources

# Manual approach
source scripts/core/environment.sh
setup_environment "entraid" "dev"
printenv | grep -E "(OIDC|ADMIN|APISIX)"
```

#### Complete System Reset
```bash
# CLI approach (recommended - single command)
./gw reset dev --clean

# Manual approach
./scripts/lifecycle/stop.sh
./scripts/lifecycle/start.sh --provider entraid --force-recreate
./scripts/bootstrap/bootstrap-core.sh dev
```

### Debug Mode

Start with debug tools for troubleshooting:

```bash
./scripts/lifecycle/start.sh --provider entraid --debug

# Access debug toolkit
docker exec -it apisix-debug-toolkit bash

# Access HTTP client
docker exec -it apisix-http-client sh
```

### Testing Framework

Run comprehensive behavior tests:

```bash
# End-to-end behavior tests
./scripts/testing/behavior-test.sh

# OIDC flow testing
./scripts/testing/test-oidc-flow.sh

# Portal backend API tests
./scripts/testing/test-portal-backend.sh
```

## 📚 Documentation

### Available Documentation

- **[CLI_USAGE.md](CLI_USAGE.md)**: Complete CLI usage guide and command reference
- **[SYSTEM_ARCHITECTURE.md](docs/SYSTEM_ARCHITECTURE.md)**: Complete technical architecture documentation
- **[MAINTAINERS_GUIDE.md](MAINTAINERS_GUIDE.md)**: Detailed maintenance and operations guide
- **[PORTAL_DEVELOPMENT.md](docs/PORTAL_DEVELOPMENT.md)**: Portal backend development guide
- **[API.md](docs/API.md)**: API endpoints and usage documentation
- **[TLS_SETUP.md](docs/TLS_SETUP.md)**: TLS termination and SSL configuration

### CLI and Script Documentation

- **`./gw --help`**: Interactive CLI command reference
- `cli/`: Python CLI implementation with Typer framework
- `scripts/lifecycle/`: Start/stop environment management
- `scripts/bootstrap/`: APISIX route configuration
- `scripts/testing/`: Comprehensive testing framework
- `scripts/debug/`: Debugging and inspection tools
- `scripts/core/environment.sh`: Configuration loading system

## 🤝 Contributing

### Development Workflow

1. **Fork and Clone**: Fork the repository and clone locally
2. **Environment Setup**: Use Keycloak for local development
3. **Make Changes**: Follow existing code patterns and architecture
4. **Test Thoroughly**: Run all test suites before submitting
5. **Documentation**: Update documentation for any architectural changes

### Code Standards

- **Scripts**: Use `set -euo pipefail` and proper error handling
- **Configuration**: Follow hierarchical config loading pattern
- **Security**: Never commit secrets, use proper authentication flows
- **Docker**: Use modular compose files with service profiles

### Testing Requirements

Before submitting PRs, ensure all tests pass:

```bash
# CLI approach (recommended)
./gw reset dev              # Test dev environment reset
./gw doctor dev             # Run comprehensive health checks
./gw reset test             # Test test environment reset
./gw doctor test            # Run comprehensive health checks

# Manual approach
./scripts/testing/behavior-test.sh  # Run full behavior test suite

# Test both providers
./scripts/lifecycle/start.sh --provider keycloak
./scripts/testing/test-oidc-flow.sh
./scripts/lifecycle/start.sh --provider entraid
./scripts/testing/test-oidc-flow.sh
```

