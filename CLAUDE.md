# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a modular Infrastructure-as-Code (IAC) implementation of Apache APISIX Gateway with multi-provider OIDC authentication support. The system includes:

- **APISIX Gateway**: Core API gateway with OIDC routing and AI provider proxying
- **Multi-Provider OIDC**: Support for Keycloak (local dev) and Microsoft EntraID (Azure AD)
- **Self-Service Portal**: Python Flask backend for API key management
- **AI Provider Gateway**: Secure proxying to OpenAI, Anthropic, and LiteLLM endpoints
- **Clean Architecture**: Separation of concerns with provider-specific configurations

## Network Architecture & Security Configuration

### Port Bindings (Current State)

**External Access Points:**
- **Port 9080**: APISIX Gateway (bound to 0.0.0.0) - ✅ **SAFE FOR EXTERNAL ACCESS**
  - Main API gateway for all client requests
  - OIDC-protected portal access
  - API key-protected AI provider endpoints
- **Port 3001**: Portal Backend (bound to 0.0.0.0) - ✅ **SAFE FOR EXTERNAL ACCESS**
  - Self-service API key management interface
  - Protected by APISIX OIDC authentication
  - Direct access bypasses OIDC (development only)

**Internal-Only Services:**
- **Port 9180**: APISIX Admin API (bound to 127.0.0.1) - 🔒 **LOCALHOST ONLY**
  - Full administrative control over APISIX configuration
  - Consumer and route management
  - **CRITICAL**: Must never be exposed externally
- **Port 2379**: etcd (container network only) - 🔒 **INTERNAL ONLY**
  - APISIX configuration storage
  - Not exposed to host network
- **Port 8080**: Keycloak (when using keycloak provider) - ⚠️ **CONDITIONAL**
  - Only active when using Keycloak provider
  - Can be exposed for development, should be restricted in production

### APISIX Route Configuration

**OIDC-Protected Routes (Authentication Required):**

1. **Portal Route**: `/portal/*`
   - **ID**: `portal-oidc-route`
   - **Methods**: GET, POST
   - **Plugin**: `openid-connect` (full OIDC flow)
   - **Headers Injected**: `X-User-Oid`, `X-User-Name`, `X-User-Email`, `X-Userinfo`, `X-Id-Token`, `X-Access-Token`
   - **Upstream**: Portal Backend (`portal-backend:3000`)
   - **Purpose**: Main portal interface for API key management

2. **OIDC Callback Route**: `/v1/auth/oidc/callback`
   - **ID**: `oidc-auth-callback`
   - **Methods**: GET, POST
   - **Plugin**: `openid-connect`
   - **Purpose**: Legacy callback endpoint for backward compatibility

**API Key-Protected Routes (API Key Required):**

3. **Anthropic AI Route**: `/v1/providers/anthropic/chat`
   - **ID**: `provider-anthropic-chat`
   - **Methods**: POST
   - **Plugin**: `key-auth` (validates API key), `proxy-rewrite`
   - **Headers**: Adds `x-api-key: $ANTHROPIC_API_KEY`, `anthropic-version: 2023-06-01`
   - **Upstream**: `api.anthropic.com:443` (HTTPS)
   - **Purpose**: Proxy to Anthropic's Claude API

4. **OpenAI Route**: `/v1/providers/openai/chat`
   - **ID**: `provider-openai-chat`
   - **Methods**: POST
   - **Plugin**: `key-auth`, `proxy-rewrite`
   - **Headers**: Adds `Authorization: Bearer $OPENAI_API_KEY`
   - **Upstream**: `api.openai.com:443` (HTTPS)
   - **Purpose**: Proxy to OpenAI's GPT API

5. **LiteLLM Route**: `/v1/providers/litellm/chat`
   - **ID**: `provider-litellm-chat`
   - **Methods**: POST
   - **Plugin**: `key-auth`, `proxy-rewrite`
   - **Headers**: Adds `Authorization: Bearer $LITELLM_KEY`
   - **Upstream**: `anast.ita.chalmers.se:4000` (HTTPS)
   - **Purpose**: Proxy to LiteLLM aggregator service

### API Key Authentication Flow

1. **User Authentication**: User logs in via OIDC (EntraID/Keycloak) at `/portal/`
2. **Consumer Creation**: Portal backend creates APISIX Consumer with username = user's OID
3. **API Key Generation**: Portal generates CSPRNG key and creates key-auth credential
4. **API Usage**: Client uses API key in `apikey` header for AI provider routes
5. **Key Validation**: APISIX validates key against Consumer credentials
6. **Proxying**: APISIX adds provider-specific headers and forwards to upstream

## Essential Commands

### Environment Management

Start the environment (default: Keycloak):
```bash
./scripts/lifecycle/start.sh
```

Start with specific provider:
```bash
./scripts/lifecycle/start.sh --provider entraid
./scripts/lifecycle/start.sh --provider keycloak
```

Start with debug mode (adds diagnostic containers):
```bash
./scripts/lifecycle/start.sh --provider entraid --debug
```

Stop all services:
```bash
./scripts/lifecycle/stop.sh
```

### Configuration Management

The project uses hierarchical configuration loading:
1. Shared config: `config/shared/` (base APISIX settings)
2. Secrets: `secrets/{provider}-{environment}.env` (credentials, gitignored)
3. Provider config: `config/providers/{provider}/` (provider-specific settings)

Load environment variables for a specific provider:
```bash
# Load configuration (used internally by scripts)
source scripts/core/environment.sh
setup_environment "entraid" "dev"
```

### Testing and Debugging

Test OIDC flow end-to-end:
```bash
OIDC_PROVIDER_NAME=entraid scripts/debug/curl-test.sh
```

Inspect configuration:
```bash
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh validate
```

Test portal backend directly:
```bash
./scripts/testing/test-portal-backend.sh
```

Test behavior flows:
```bash
./scripts/testing/behavior-test.sh
```

Test OIDC flow specifically:
```bash
./scripts/testing/test-oidc-flow.sh
```

Debug containers (when started with --debug):
```bash
# Access debug toolkit with curl, jq, etc.
docker exec -it apisix-debug-toolkit bash

# Access HTTP client
docker exec -it apisix-http-client sh
```

### APISIX Management

Check routes:
```bash
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes
```

Check consumers:
```bash
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/consumers
```

Check APISIX health (uses built-in admin API):
```bash
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes
```

View logs:
```bash
docker compose -f infrastructure/docker/base.yml logs -f
docker logs apisix-dev
docker logs portal-backend-dev
```

### Portal Backend Development

Test portal backend health:
```bash
curl http://localhost:3001/health
```

Test with user headers (bypass OIDC for development):
```bash
curl -H "X-User-Oid: test-user-123" \
     -H "X-User-Name: Test User" \
     -H "X-User-Email: test@example.com" \
     http://localhost:3001/portal/
```

Generate API key:
```bash
curl -X POST \
     -H "X-User-Oid: test-user-123" \
     http://localhost:3001/portal/get-key
```

Development admin interface (when DEV_MODE=true):
```bash
# Access development admin UI at http://localhost:3001/dev/admin/
# Requires DEV_ADMIN_PASSWORD for authentication
# Provides user simulation, key management testing, and reset capabilities
```

## Architecture Overview

### Core Infrastructure Components

- **etcd**: Configuration store for APISIX (`etcd-dev` container)
- **APISIX Gateway**: Main gateway service (`apisix-dev` container on port 9080)
- **APISIX Admin**: Admin API and dashboard (`apisix-dev` container on port 9180, localhost-only)
- **Portal Backend**: Self-service API key management (`portal-backend-dev` on port 3001)

### Provider Services

- **Keycloak**: Local OIDC provider for development (`keycloak-dev` on port 8080)
- **EntraID**: External Microsoft Azure AD (no container, configured via secrets)

### Configuration Architecture

The system implements clean separation of concerns:

```
config/
├── shared/           # Common APISIX settings
│   ├── base.env     # Core configuration
│   └── apisix.env   # APISIX admin keys
├── providers/       # Provider-specific configs
│   ├── entraid/dev.env
│   └── keycloak/dev.env
secrets/             # Credentials (gitignored)
├── entraid-dev.env
└── keycloak-dev.env
```

### Docker Compose Architecture

Modular compose files with profiles:

- `infrastructure/docker/base.yml`: Core services (etcd, apisix, portal-backend)
- `infrastructure/docker/providers.yml`: Provider services with profiles (keycloak, entraid)
- `infrastructure/docker/debug.yml`: Debug tools (debug-toolkit, http-client)

### Script Organization

```
scripts/
├── core/
│   └── environment.sh    # Configuration loading functions
├── lifecycle/
│   ├── start.sh         # Universal startup script
│   └── stop.sh          # Universal stop script
├── bootstrap/
│   └── bootstrap.sh     # OIDC route configuration
├── debug/
│   ├── curl-test.sh     # OIDC flow testing
│   └── inspect-config.sh # Configuration validation
└── testing/
    ├── behavior-test.sh      # End-to-end behavior tests
    ├── test-portal-backend.sh # Portal backend API tests
    └── test-oidc-flow.sh     # OIDC flow tests
```

### Portal Backend Architecture

The Self-Service API Key Portal is a Python Flask application:

- **Technology**: Flask + Gunicorn for production
- **Authentication**: Relies on APISIX header injection (`X-User-Oid`, `X-User-Name`, `X-User-Email`)
- **APISIX Integration**: Uses Admin API for Consumer/Credential management
- **Security**: CSPRNG-based key generation, no full keys in logs
- **User Model**: 1:1 mapping between OIDC users and APISIX Consumers

Key endpoints:
- `/portal/` - Dashboard showing API key status
- `/portal/get-key` - Generate or retrieve API key
- `/portal/recycle-key` - Rotate existing API key
- `/health` - Health check endpoint

## Current Security Configuration

### Admin API Security (CRITICAL)

**Status**: 🔒 **SECURED** - Admin API bound to localhost only (`127.0.0.1:9180`)

**What this means:**
- External access to admin API is **blocked**
- Internal container communication still works (`apisix-dev:9180`)
- Portal backend functionality **unaffected**
- Full APISIX control **not accessible** from internet

**Verification:**
```bash
# Should work (localhost)
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# Should fail (external IP)
curl -H "X-API-KEY: $ADMIN_KEY" http://YOUR-EXTERNAL-IP:9180/apisix/admin/routes
```

### External Access Security Matrix

| Port | Service | Binding | External Safe? | Purpose |
|------|---------|---------|----------------|---------|
| 9080 | APISIX Gateway | 0.0.0.0 | ✅ YES | Client requests, OIDC protected |
| 9180 | APISIX Admin | 127.0.0.1 | 🔒 INTERNAL ONLY | Admin API, never expose |
| 3001 | Portal Backend | 0.0.0.0 | ✅ YES | Portal access, OIDC protected |
| 2379 | etcd | container | 🔒 INTERNAL ONLY | Database, container network |
| 8080 | Keycloak | 0.0.0.0 | ⚠️ DEV ONLY | OIDC provider, dev environment |

### Authentication & Authorization Architecture

**OIDC Flow (Portal Access):**
1. User → `http://gateway:9080/portal/`
2. APISIX → Redirect to OIDC provider (EntraID/Keycloak)
3. User authenticates with OIDC provider
4. Provider → Callback to APISIX
5. APISIX → Validates token, injects headers, forwards to portal backend
6. Portal backend → Sees user headers, provides interface

**API Key Flow (AI Provider Access):**
1. Client → `POST http://gateway:9080/v1/providers/anthropic/chat` with `apikey: USER_KEY`
2. APISIX → Validates key against Consumer database
3. APISIX → Adds provider-specific authentication headers
4. APISIX → Proxies to upstream provider (api.anthropic.com)
5. Provider → Returns response through APISIX to client

### Secret Management

**Environment Variables (Sensitive):**
- `ADMIN_KEY`: APISIX admin API key (in container env only)
- `OIDC_CLIENT_SECRET`: OIDC provider secret
- `ANTHROPIC_API_KEY`: Anthropic API key for proxying
- `OPENAI_API_KEY`: OpenAI API key for proxying
- `LITELLM_KEY`: LiteLLM service key

**Files (gitignored):**
- `secrets/entraid-dev.env`: EntraID credentials
- `secrets/keycloak-dev.env`: Keycloak credentials (optional)

## Key Development Patterns

### Testing Framework

The project includes a comprehensive testing framework with structured test results:

```
tests/
├── results/                    # Test run results with timestamps
│   └── {timestamp}/
│       ├── artifacts/         # Service status and logs
│       ├── processed/         # Processed test summaries
│       ├── raw/              # Raw test responses
│       └── test-run-metadata.json
├── expected-behavior/          # Expected behavior definitions
│   ├── consumer-management.json
│   ├── oidc-flow.json
│   └── portal-backend-api.json
└── README.md                  # Testing framework documentation
```

### Provider Switching

The system supports clean provider switching via environment variables or CLI args:

```bash
# Environment variable approach
export OIDC_PROVIDER_NAME=entraid
./scripts/lifecycle/start.sh

# CLI approach (preferred)
./scripts/lifecycle/start.sh --provider entraid
```

### Configuration Loading

Environment configuration follows a hierarchical pattern implemented in `scripts/core/environment.sh`:

1. Load shared config (`config/shared/`)
2. Load secrets (`secrets/{provider}-{environment}.env`)
3. Load provider config (`config/providers/{provider}/`)
4. Generate dynamic values (discovery URLs, etc.)
5. Validate required variables

### Error Handling

Scripts use `set -euo pipefail` for strict error handling and include comprehensive logging functions:
- `log_info()`, `log_success()`, `log_warning()`, `log_error()`, `log_debug()`

### Container Naming

Containers follow the pattern: `{service}-{environment}` (e.g., `apisix-dev`, `etcd-dev`)

## External Deployment Preparation

### Required Changes for Public Exposure

**1. Update Redirect URIs:**
```bash
# In config/providers/entraid/dev.env
OIDC_REDIRECT_URI=https://your-domain.com/portal/callback
```

**2. Update EntraID App Registration:**
- Add public domain redirect URI
- Verify tenant and client configuration

**3. TLS Termination (Recommended):**
```bash
# Example with nginx reverse proxy
# 443 → APISIX Gateway (9080)
# Admin API stays internal-only
```

**4. Firewall Configuration:**
```bash
# Allow required external access
sudo ufw allow 443/tcp   # HTTPS (with TLS termination)
sudo ufw allow 80/tcp    # HTTP (redirect to HTTPS)

# Block admin API (defense in depth)
sudo ufw deny 9180/tcp

# Optional: Allow direct gateway access
sudo ufw allow 9080/tcp
sudo ufw allow 3001/tcp
```

### Security Hardening Checklist

- ✅ Admin API bound to localhost only
- ✅ Secrets separated from version control
- ✅ API keys use CSPRNG generation
- ✅ No full keys logged (only fingerprints)
- ✅ OIDC authentication for portal access
- ✅ API key authentication for provider access
- ⚠️ TLS termination needed for production
- ⚠️ Rate limiting should be configured
- ⚠️ WAF policies should be reviewed

## Common Troubleshooting Patterns

### Configuration Issues
- Use `inspect-config.sh` to validate configuration
- Check that secrets files exist and contain non-placeholder values
- Verify environment variable loading with `printenv | grep -E "(OIDC|ADMIN|APISIX)"`

### Service Health Issues
- Check container logs: `docker logs {container-name}`
- Verify service health endpoints
- Use debug containers for network connectivity testing

### Portal Backend Issues
- Test health endpoint: `curl http://localhost:3001/health`
- Check user header injection from APISIX
- Verify APISIX Admin API connectivity from portal container

### OIDC Issues
- Validate discovery endpoint: `curl $OIDC_DISCOVERY_ENDPOINT`
- Check redirect URI configuration
- Verify client ID/secret in provider and config

### API Key Issues
- Check consumer exists: `curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/consumers`
- Verify key-auth credentials
- Test key validation manually

## Recent Security Improvements (2024-12)

### Critical Admin API Security Fix
**Issue**: Admin API was exposed externally on port 9180, allowing full APISIX control
**Solution**: Bound admin API to localhost only (`127.0.0.1:9180`)
**Impact**:
- ✅ External admin access blocked
- ✅ Internal container communication preserved
- ✅ Portal backend functionality unaffected
- ✅ Zero functionality loss for legitimate use

### OIDC Connectivity Enhancement
**Issue**: OIDC flow failing with external providers (EntraID)
**Solution**: Added DNS configuration to APISIX container
**Impact**:
- ✅ External OIDC providers now accessible
- ✅ EntraID authentication works reliably
- ✅ Network diagnostic tools available in containers

### Docker Configuration Hardening
**Improvements**:
- ✅ Volume conflict resolution
- ✅ Consistent container networking
- ✅ Automatic service startup reliability
- ✅ Environment variable loading fixes

## Important File Patterns and Conventions

### Files to Never Modify
- `old/` directory: Contains archived legacy implementation
- `apisix-source-repo/`: Apache APISIX source code (read-only reference)
- `secrets/` files: Should be updated by admin, not in version control

### Key Implementation Patterns
- **Configuration Hierarchy**: Always use `scripts/core/environment.sh` for environment loading
- **Container Naming**: Follow `{service}-{environment}` pattern (e.g., `apisix-dev`, `portal-backend-dev`)
- **Script Standards**: All scripts use `set -euo pipefail` and include logging functions
- **Docker Compose**: Modular compose files with service profiles for clean separation
- **Error Handling**: Comprehensive error checking with specific error messages for troubleshooting

### Portal Backend Code Structure
- **Main Application**: `portal-backend/src/app.py` - Flask app with APISIX Admin API integration
- **Templates**: `portal-backend/templates/` - HTML templates for dashboard UI
- **Architecture Pattern**: Clean separation between user identity resolution, consumer management, and credential operations
- **Security Pattern**: Never log full API keys, only fingerprints using `APIKey.get_fingerprint()`
- **Development Guide**: `docs/PORTAL_DEVELOPMENT.md` - Comprehensive development workflows, testing strategies, and debugging guides

## Key Environment Variables

Essential variables loaded by the environment system:
- `OIDC_PROVIDER_NAME`: Current provider (keycloak/entraid)
- `ADMIN_KEY`: APISIX admin API key (localhost access only)
- `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`: Provider credentials
- `OIDC_DISCOVERY_ENDPOINT`: Provider discovery URL
- `APISIX_NODE_LISTEN`: Gateway port (default: 9080)
- `APISIX_ADMIN_PORT`: Admin API port (default: 9180, localhost-only)
- `APISIX_ADMIN_API_CONTAINER`: Internal container endpoint for portal backend
- `DEV_MODE`, `DEV_ADMIN_PASSWORD`: Development mode settings (optional)
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `LITELLM_KEY`: AI provider credentials

## API Usage Examples

### Portal Access (OIDC Protected)
```bash
# Access portal (triggers OIDC flow)
curl -I http://localhost:9080/portal/

# Should redirect to OIDC provider login
```

### AI Provider Access (API Key Protected)
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

# LiteLLM (local models)
curl -X POST http://localhost:9080/v1/providers/litellm/chat \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR-API-KEY" \
  -d '{
    "model": "ollama/llama3.3",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Admin API Access (Localhost Only)
```bash
# Check all routes
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# Check consumers
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/consumers

# Check specific consumer credentials
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/consumers/USER-OID/credentials
```

---

This implementation provides a robust, secure, and scalable foundation for APISIX Gateway with multi-provider OIDC support and AI provider proxying, following Infrastructure-as-Code best practices with defense-in-depth security.