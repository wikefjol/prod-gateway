# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a modular Infrastructure-as-Code (IAC) implementation of Apache APISIX Gateway with multi-provider OIDC authentication support. The system includes:

- **APISIX Gateway**: Core API gateway with OIDC routing
- **Multi-Provider OIDC**: Support for Keycloak (local dev) and Microsoft EntraID (Azure AD)
- **Self-Service Portal**: Python Flask backend for API key management
- **Clean Architecture**: Separation of concerns with provider-specific configurations

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

## Architecture Overview

### Core Infrastructure Components

- **etcd**: Configuration store for APISIX (`etcd-dev` container)
- **APISIX Gateway**: Main gateway service (`apisix-dev` container on port 9080)
- **APISIX Admin**: Admin API and dashboard (`apisix-dev` container on port 9180)
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

## Key Development Patterns

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

## Implemented Fixes and Improvements

### OIDC Connectivity Fixes

**Issue**: OIDC flow failing with "network is unreachable" when accessing external providers like Microsoft EntraID.

**Solution**: Added DNS configuration and network diagnostic tools to APISIX container.

Files modified:
- `infrastructure/docker/base.yml`: Added `dns: [8.8.8.8, 1.1.1.1]` to apisix-dev service
- `apisix/Dockerfile`: Added network diagnostic tools (curl, dnsutils, iputils-ping, telnet)

**Verification**: OIDC flow now successfully redirects to Microsoft EntraID login page.

### Portal Backend Auto-Start Fix

**Issue**: Portal backend service not starting automatically with main services.

**Solution**: Explicitly include portal-backend in Docker Compose startup command.

Files modified:
- `scripts/lifecycle/start.sh`: Updated startup command to explicitly include services:
  ```bash
  "${compose_cmd[@]}" "${up_args[@]}" etcd-dev apisix-dev loader-dev portal-backend
  ```

### Docker Volume Conflict Resolution

**Issue**: Volume conflict errors when stopping services: "conflicting parameters 'external' and 'driver' specified"

**Solution**: Made volume definitions consistent across all Docker Compose files.

Files modified:
- `infrastructure/docker/debug.yml`: Set `apisix_logs: external: false`
- Removed obsolete `version: '3.8'` declarations from compose files

### Environment Variable Loading Fix

**Issue**: Stop script failing due to missing environment variables.

**Solution**: Added environment loading to stop script.

Files modified:
- `scripts/lifecycle/stop.sh`: Added environment setup call:
  ```bash
  setup_environment "${OIDC_PROVIDER_NAME:-keycloak}" "${ENVIRONMENT:-dev}" 2>/dev/null || true
  ```

### Health Endpoint Optimization

**Issue**: Custom health endpoint returning 404 Route Not Found.

**Solution**: Replaced custom health route with APISIX's built-in admin API endpoints.

**Rationale**: Built-in endpoints are more reliable, maintained by APISIX team, and reduce custom code complexity.

Files modified:
- `scripts/debug/curl-test.sh`: Updated health check to use admin API:
  ```bash
  curl -H "X-API-KEY: $ADMIN_KEY" "$APISIX_ADMIN_API/routes"
  ```
- `scripts/bootstrap/bootstrap.sh`: Removed custom health route configuration

### System Status After Fixes

**✅ All Critical Issues Resolved**:
- OIDC authentication flow works with Microsoft EntraID
- Portal backend starts automatically
- No Docker volume conflicts
- Health checks use reliable built-in endpoints
- All test scripts pass successfully

**Test Commands**:
```bash
# Test full OIDC flow
OIDC_PROVIDER_NAME=entraid scripts/debug/curl-test.sh

# Test health endpoint
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# Test portal access (should redirect to Microsoft login)
curl -I http://localhost:9080/portal/
```

## Files to Never Modify

- `old/` directory: Contains archived legacy implementation
- `apisix-source-repo/`: Apache APISIX source code (read-only reference)
- `secrets/` files: Should be updated by admin, not in version control

## Key Environment Variables

Essential variables loaded by the environment system:
- `OIDC_PROVIDER_NAME`: Current provider (keycloak/entraid)
- `ADMIN_KEY`: APISIX admin API key
- `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`: Provider credentials
- `OIDC_DISCOVERY_ENDPOINT`: Provider discovery URL
- `APISIX_NODE_LISTEN`: Gateway port (default: 9080)
- `APISIX_ADMIN_PORT`: Admin API port (default: 9180)