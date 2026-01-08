# APISIX Gateway with EntraID OIDC Authentication

A simplified, production-ready implementation of Apache APISIX Gateway with EntraID OIDC authentication and AI provider proxying capabilities.

## 🚀 Features

- **EntraID OIDC Authentication**: Microsoft EntraID (Azure AD) integration for secure access
- **Self-Service Portal**: Python Flask backend for API key management
- **AI Provider Gateway**: Secure proxying to OpenAI, Anthropic, and LiteLLM endpoints
- **Environment Separation**: Clean isolation between dev and test environments
- **Security Hardening**: Admin API localhost-only binding and proper authentication flows
- **Simple Architecture**: Streamlined Docker Compose setup with direct commands

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [System Requirements](#-system-requirements)
- [Architecture Overview](#-architecture-overview)
- [Configuration](#-configuration)
- [Usage Examples](#-usage-examples)
- [Security Features](#-security-features)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

## ⚡ Quick Start

### Prerequisites

- Docker & Docker Compose V2
- curl (for testing)
- bash (scripts are bash-based)
- EntraID application registration with client credentials

### Simple Setup

The gateway uses environment-specific scripts for easy management:

```bash
# Start development environment
./scripts/dev.sh reset

# Check system status
./scripts/dev.sh status

# View configured routes
./scripts/dev.sh routes

# View all commands
./scripts/dev.sh help
```

### Environment Management

```bash
# Development environment (ports 9080, 9180, 3001)
./scripts/dev.sh up
./scripts/dev.sh down
./scripts/dev.sh reset

# Test environment (ports 9081, 9181, 3002)
./scripts/test.sh up
./scripts/test.sh down
./scripts/test.sh reset
```

### Test the Setup

```bash
# Check system health
curl http://localhost:9080/health

# Test the portal (triggers OIDC flow)
curl -I http://localhost:9080/portal/

# View all configured routes
./scripts/dev.sh routes
```

## 🔧 System Requirements

### Minimum Requirements

- **OS**: Linux (Ubuntu 20.04+ recommended), macOS, or Windows with WSL2
- **Memory**: 4GB RAM minimum, 8GB+ recommended
- **Storage**: 2GB free space for Docker images
- **Docker**: Version 20.10+ with Docker Compose V2

### Port Usage

| Environment | Gateway | Admin API | Portal |
|-------------|---------|-----------|--------|
| Development | 9080 | 9180 | 3001 |
| Test | 9081 | 9181 | 3002 |

All admin ports are bound to localhost (127.0.0.1) for security.

## 🏗️ Architecture Overview

### Service Architecture

```
Internet → APISIX Gateway → Portal Backend → OIDC Provider (EntraID)
                ↓
        Admin API (localhost only)
                ↓
        etcd (configuration store)
```

### Core Components

- **APISIX Gateway**: Core API gateway with OIDC routing and AI provider proxying
- **Portal Backend**: Python Flask self-service API key management
- **etcd**: Configuration store for APISIX routes and settings
- **EntraID OIDC**: Microsoft Azure AD authentication provider

### File Structure

```
├── docker-compose.yml           # Base services
├── docker-compose.dev.yml       # Development environment overrides
├── docker-compose.test.yml      # Test environment overrides
├── .env.dev                     # Development configuration
├── .env.test                    # Test configuration
├── scripts/
│   ├── dev.sh                   # Development environment management
│   ├── test.sh                  # Test environment management
│   └── bootstrap.sh             # Route loading script
├── apisix/                      # Route JSON configurations
├── portal-backend/              # Flask API key management service
└── secrets/                     # EntraID credentials (gitignored)
    ├── entraid-dev.env          # Development secrets
    └── entraid-test.env         # Test secrets
```

## ⚙️ Configuration

### Environment Configuration

The system uses simple `.env` files for each environment:

- `.env.dev` - Development environment configuration
- `.env.test` - Test environment configuration

### EntraID Setup

1. **Create secrets files** (use your actual EntraID credentials):
```bash
# Copy from your existing secrets or create new ones
cp secrets/entraid-dev.env.example secrets/entraid-dev.env
cp secrets/entraid-test.env.example secrets/entraid-test.env
```

2. **Configure your EntraID app registration**:
   - Redirect URI: `https://your-domain.com/portal/callback`
   - Required API permissions for user profile access

### API Provider Keys (Optional)

For AI provider routes, set these in your secrets files:
```bash
OPENAI_API_KEY=your_openai_key
ANTHROPIC_API_KEY=your_anthropic_key
LITELLM_KEY=your_litellm_key
```

## 📖 Usage Examples

### Environment Management

```bash
# Start development environment with bootstrap
./scripts/dev.sh reset

# Start test environment
./scripts/test.sh up

# View logs for specific service
./scripts/dev.sh logs apisix --follow

# Check route configuration
./scripts/dev.sh routes
```

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
```

## 🔒 Security Features

### Current Security Measures

- ✅ **Admin API Security**: Bound to localhost only (`127.0.0.1`)
- ✅ **OIDC Authentication**: Full OpenID Connect flow for portal access
- ✅ **API Key Authentication**: Secure CSPRNG key generation for API access
- ✅ **Environment Isolation**: Complete separation between dev and test
- ✅ **Secret Management**: Gitignored secrets with example templates
- ✅ **Network Security**: Proper container networking and port binding

### Security Model

1. **Portal Access**: EntraID OIDC authentication → Header injection → Portal backend
2. **API Usage**: API key validation → Provider-specific routing → Upstream proxy
3. **Admin Access**: Localhost-only binding prevents external admin API access

## 🐛 Troubleshooting

### Common Issues

#### Services Won't Start
```bash
# Check Docker status and conflicts
docker info
docker compose ps

# Check logs for errors
./scripts/dev.sh logs apisix
```

#### OIDC Authentication Fails
```bash
# Check EntraID configuration
./scripts/dev.sh logs portal-backend

# Verify secrets are loaded
grep ENTRAID_CLIENT_ID secrets/entraid-dev.env
```

#### Routes Not Loading
```bash
# Check bootstrap process
./scripts/dev.sh bootstrap

# Verify admin API access
curl -H "X-API-KEY: a22ce33c74f8ac8ed75b2e10eba16e7f4a0b9a7a8e8db4fdc5b5e4ca4a10dc7a4" \
     http://localhost:9180/apisix/admin/routes
```

### Complete Reset
```bash
# Full environment cleanup and restart
./scripts/dev.sh down --clean
./scripts/dev.sh reset
```

## 🤝 Contributing

### Development Workflow

1. **Environment Setup**: Use development environment for testing
2. **Make Changes**: Follow existing patterns for Docker Compose and scripts
3. **Test Both Environments**: Validate dev and test environments work
4. **Update Documentation**: Ensure README reflects any changes

### Testing Requirements

Before submitting changes:
```bash
# Test development environment
./scripts/dev.sh reset
./scripts/dev.sh status

# Test test environment
./scripts/test.sh reset
./scripts/test.sh status

# Verify route loading
./scripts/dev.sh routes
./scripts/test.sh routes
```

## 🏷️ Version

This is a simplified architecture version that removes the previous complex Python CLI and multi-provider configuration system while maintaining full functionality and environment separation.