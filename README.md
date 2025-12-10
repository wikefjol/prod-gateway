# APISIX Gateway with Multi-Provider OIDC

A clean, modular Infrastructure-as-Code (IAC) implementation of APISIX Gateway with support for multiple OIDC providers including Keycloak and Microsoft EntraID (Azure AD).

## Quick Start

### Start with Default Provider (Keycloak)
```bash
./scripts/lifecycle/start.sh
```

### Start with EntraID
```bash
./scripts/lifecycle/start.sh --provider entraid
```

### Start with Debug Mode
```bash
./scripts/lifecycle/start.sh --provider entraid --debug
```

### Stop Environment
```bash
./scripts/lifecycle/stop.sh
```

## Architecture & Design Principles

### Clean IAC Implementation
- **Separation of Concerns**: Provider configs separate from core infrastructure
- **Single Source of Truth**: Hierarchical configuration management
- **Provider Abstraction**: Clean interfaces for switching between OIDC providers
- **Debug-First**: Enhanced containers with curl and diagnostic tools
- **Security**: Sensitive data in separate gitignored files
- **No Coupling**: Avoid hardcoding and tight coupling between components

### Directory Structure
```
├── config/                          # Modular configuration
│   ├── providers/
│   │   ├── entraid/dev.env         # EntraID-specific settings
│   │   ├── keycloak/dev.env        # Keycloak-specific settings
│   │   └── shared/
│   │       ├── base.env            # Common APISIX settings
│   │       └── apisix.env          # APISIX admin keys
├── infrastructure/docker/           # Modular Docker Compose
│   ├── base.yml                    # Core services (etcd, apisix)
│   ├── providers.yml               # Provider services with profiles
│   └── debug.yml                   # Debug toolkit with curl
├── scripts/
│   ├── core/environment.sh         # Configuration management
│   ├── lifecycle/
│   │   ├── start.sh                # Universal startup script
│   │   └── stop.sh                 # Universal stop script
│   ├── bootstrap/bootstrap.sh      # OIDC route configuration
│   └── debug/
│       ├── curl-test.sh            # OIDC flow testing
│       └── inspect-config.sh       # Configuration inspector
├── secrets/                        # Sensitive credentials (gitignored)
│   ├── entraid-dev.env             # EntraID credentials
│   └── keycloak-dev.env            # Keycloak credentials (optional)
└── old/                            # Legacy implementation (archived)
```

## Configuration Management

### Configuration Loading Hierarchy
1. **Shared Config**: Common APISIX settings (`config/shared/`)
2. **Secrets**: Provider credentials (`secrets/{provider}-{environment}.env`)
3. **Provider Config**: Provider-specific settings (`config/providers/{provider}/`)

### Provider Switching
```bash
# Environment variable approach
export OIDC_PROVIDER_NAME=entraid
./scripts/lifecycle/start.sh

# Command line approach (recommended)
./scripts/lifecycle/start.sh --provider entraid

# With additional options
./scripts/lifecycle/start.sh --provider keycloak --debug --force-recreate
```

## Supported OIDC Providers

### Keycloak (Local Development)
- **Setup**: Automatic via Docker Compose
- **Admin**: `http://localhost:8080` (admin/admin)
- **Discovery**: `http://keycloak-dev:8080/realms/quickstart/.well-known/openid-connect/configuration`
- **Configuration**: Ready out-of-the-box

### Microsoft EntraID (Azure AD)
- **Setup**: Requires admin configuration
- **Discovery**: `https://login.microsoftonline.com/{tenant}/v2.0/.well-known/openid-connect/configuration`
- **Configuration**: Update `secrets/entraid-dev.env` with actual credentials

## Provider Setup

### Keycloak Setup
Keycloak works out-of-the-box:
```bash
./scripts/lifecycle/start.sh --provider keycloak
```

### EntraID Setup

#### 1. Configure Credentials
Your admin should update `secrets/entraid-dev.env`:
```bash
# Replace with actual EntraID values
ENTRAID_CLIENT_ID=your-application-client-id
ENTRAID_CLIENT_SECRET=your-client-secret-value
ENTRAID_TENANT_ID=your-azure-tenant-id
ENTRAID_SESSION_SECRET=$(openssl rand -hex 16)
```

#### 2. Start EntraID Environment
```bash
./scripts/lifecycle/start.sh --provider entraid
```

#### 3. Validate Configuration
```bash
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh validate
```

## Services & Endpoints

| Service | Port | Description | Access |
|---------|------|-------------|--------|
| APISIX Gateway | 9080 | Main API gateway | `http://localhost:9080` |
| APISIX Admin | 9180 | Admin API & dashboard | `http://localhost:9180` |
| Keycloak | 8080 | Keycloak (when using keycloak profile) | `http://localhost:8080` |

### OIDC Protected Endpoints
- **Portal**: `http://localhost:9080/portal` - Protected by OIDC
- **Legacy Callback**: `http://localhost:9080/v1/auth/oidc/callback` - OIDC callback endpoint

## Portal Backend Service

The Self-Service API Key Portal Backend is a Python Flask application that enables authenticated users to manage their APISIX API keys through a simple web interface.

### Architecture

- **Technology**: Python Flask with Gunicorn production server
- **Container**: `portal-backend-dev` running on port 3001 (external), 3000 (internal)
- **Authentication**: APISIX header injection (`X-User-Oid`, `X-User-Name`, `X-User-Email`)
- **Integration**: APISIX Admin API for Consumer/Credential management
- **Security**: CSPRNG-based key generation using `secrets.token_urlsafe(32)`

### Self-Service API Key Management

The portal implements a complete self-service workflow following the v0 specification:

#### User Workflow
1. **Navigate**: User visits `http://localhost:9080/portal/`
2. **Authentication**: APISIX redirects to EntraID/Keycloak for OIDC authentication
3. **Header Injection**: APISIX injects user identity headers after successful authentication
4. **Portal Access**: User sees dashboard with current API key status
5. **Key Management**: User can generate new keys or recycle existing keys

#### Key Management Operations

**Get Key Operation (`/portal/get-key`):**
- If exactly one credential exists: return existing key
- If none exist: generate new key and create credential
- Enforces exactly 0 or 1 key-auth credential per user (1:1 mapping)

**Recycle Key Operation (`/portal/recycle-key`):**
- If none exist: treat as "Get key" operation
- If one exists: generate new key and update credential
- Previous key becomes immediately invalid

#### Consumer Management
- **1:1 Mapping**: One OIDC user = one APISIX Consumer
- **Automatic Creation**: Consumers created automatically on first portal access
- **Consumer Username**: Uses OIDC user OID as Consumer username
- **Metadata**: Consumers tagged with creation timestamp and source information

### API Endpoints

| Endpoint | Method | Description | Headers Required |
|----------|--------|-------------|------------------|
| `/portal/` | GET | Dashboard interface showing key status | `X-User-Oid` |
| `/portal/get-key` | POST | Generate or retrieve API key | `X-User-Oid` |
| `/portal/recycle-key` | POST | Rotate/recycle API key | `X-User-Oid` |
| `/health` | GET | Health check endpoint | None |

### Development Setup

#### Full Stack Development
```bash
# Start complete stack with portal backend
./scripts/lifecycle/start.sh --provider entraid

# Access portal through APISIX (OIDC protected)
open http://localhost:9080/portal/

# Check portal backend health
curl http://localhost:3001/health
```

#### Direct Backend Development
For development without OIDC (requires user identity headers):
```bash
# Direct backend access with simulated user
curl -H "X-User-Oid: test-user-123" \
     -H "X-User-Name: Test User" \
     -H "X-User-Email: test@example.com" \
     http://localhost:3001/portal/

# Generate API key
curl -X POST \
     -H "X-User-Oid: test-user-123" \
     -H "X-User-Name: Test User" \
     -H "X-User-Email: test@example.com" \
     http://localhost:3001/portal/get-key

# Recycle API key
curl -X POST \
     -H "X-User-Oid: test-user-123" \
     http://localhost:3001/portal/recycle-key
```

### Portal Backend Configuration

The portal backend uses environment variables for APISIX integration:

```bash
# Core APISIX integration
ADMIN_KEY=your-admin-key
APISIX_ADMIN_API_CONTAINER=http://apisix-dev:9180/apisix/admin
APISIX_ADMIN_API=http://localhost:9180/apisix/admin

# Environment context
ENVIRONMENT=dev
PORTAL_BACKEND_HOST=portal-backend:3000
```

### Security Features

1. **Secure Key Generation**: Uses Python `secrets` module with CSPRNG
2. **Key Fingerprinting**: Only logs partial key fingerprints (`key[:8]...key[-4:]`)
3. **No Key Logging**: Full API keys never appear in logs
4. **Header Validation**: Validates required user identity headers
5. **APISIX Integration**: All key operations go through APISIX Admin API
6. **Non-root Container**: Runs as `portal` user (UID:GID managed)

### Portal Backend Troubleshooting

#### Issue: Portal Backend Not Starting
**Symptoms**: Container fails to start or health check fails
**Solution**:
```bash
# Check container logs
docker logs portal-backend-dev

# Verify environment variables
docker exec portal-backend-dev env | grep -E "(ADMIN_KEY|APISIX)"

# Check health endpoint directly
curl http://localhost:3001/health
```

#### Issue: User Identity Headers Missing
**Symptoms**: "Authentication required" error in portal
**Solution**:
1. Verify OIDC authentication is working: `curl -v http://localhost:9080/portal/`
2. Check APISIX route configuration includes header injection
3. Review bootstrap logs: `docker logs apisix-loader-dev`

#### Issue: APISIX Admin API Connection Failed
**Symptoms**: Portal shows "Internal server error" or credential operations fail
**Solution**:
```bash
# Test APISIX Admin API connectivity from portal backend
docker exec portal-backend-dev curl -H "X-API-KEY: $ADMIN_KEY" \
  http://apisix-dev:9180/apisix/admin/consumers

# Verify ADMIN_KEY is correctly set
docker exec portal-backend-dev printenv ADMIN_KEY

# Check network connectivity
docker exec portal-backend-dev ping apisix-dev
```

#### Issue: Consumer Creation Fails
**Symptoms**: Logs show "Consumer creation failed" or ETCD errors
**Solution**:
1. Verify ADMIN_KEY has sufficient privileges
2. Check ETCD health: `docker exec etcd-dev etcdctl endpoint health`
3. Review Consumer data format in logs for forbidden fields
4. Test Consumer API manually:
```bash
curl -X PUT -H "X-API-KEY: $ADMIN_KEY" \
     -H "Content-Type: application/json" \
     -d '{"username":"test","desc":"test consumer"}' \
     http://localhost:9180/apisix/admin/consumers/test
```

## Debug & Troubleshooting

### Debug Mode
Start with enhanced debugging capabilities:
```bash
./scripts/lifecycle/start.sh --provider entraid --debug
```

This provides additional containers:
- **Debug Toolkit**: `docker exec -it apisix-debug-toolkit bash`
- **HTTP Client**: `docker exec -it apisix-http-client sh`
- **Config Inspector**: Available via debug scripts

### Configuration Inspection
```bash
# Full configuration inspection
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh

# Specific sections
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh oidc
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh validate
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh network
```

### OIDC Flow Testing
```bash
# Test all endpoints
OIDC_PROVIDER_NAME=entraid scripts/debug/curl-test.sh

# Test specific components
OIDC_PROVIDER_NAME=entraid scripts/debug/curl-test.sh discovery
OIDC_PROVIDER_NAME=entraid scripts/debug/curl-test.sh portal
OIDC_PROVIDER_NAME=entraid scripts/debug/curl-test.sh admin
```

### Common Debug Scenarios

#### Test OIDC Discovery
```bash
# Inside debug container
docker exec -it apisix-debug-toolkit bash
curl -s $OIDC_DISCOVERY_ENDPOINT | jq .
```

#### Test Portal Access
```bash
# Should redirect to OIDC provider
curl -v http://localhost:9080/portal/
```

#### Check APISIX Routes
```bash
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes
```

## Common Usage Patterns

### Development Workflow
```bash
# 1. Start Keycloak environment for initial development
./scripts/lifecycle/start.sh --provider keycloak

# 2. Test OIDC flows
OIDC_PROVIDER_NAME=keycloak scripts/debug/curl-test.sh

# 3. Switch to EntraID for integration testing
./scripts/lifecycle/stop.sh
./scripts/lifecycle/start.sh --provider entraid --debug

# 4. Validate EntraID setup
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh validate

# 5. Test EntraID flows
OIDC_PROVIDER_NAME=entraid scripts/debug/curl-test.sh
```

### Production Checklist
- [ ] Update `secrets/entraid-dev.env` with production credentials
- [ ] Verify OIDC discovery endpoint accessibility
- [ ] Test complete OIDC flow end-to-end
- [ ] Configure proper redirect URIs in EntraID application
- [ ] Set up monitoring and logging
- [ ] Review security settings and session configuration

## Troubleshooting Guide

### Issue: EntraID Placeholder Values
**Symptoms**: Configuration validation shows placeholder warnings
**Solution**: Update `secrets/entraid-dev.env` with actual credentials from your admin

### Issue: OIDC Discovery Endpoint Not Accessible
**Symptoms**: Discovery endpoint tests fail
**Solution**:
1. Verify tenant ID in discovery URL
2. Check network connectivity from container
3. Ensure EntraID application is properly configured

### Issue: Portal Route Returns 404
**Symptoms**: Portal endpoint not found
**Solution**:
1. Check if routes were configured: `curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes`
2. Review bootstrap logs: `docker logs apisix-loader-dev`
3. Restart with force recreate: `./scripts/lifecycle/start.sh --provider entraid --force-recreate`

### Issue: Provider Switching Not Working
**Symptoms**: Wrong provider configuration loaded
**Solution**:
1. Stop current environment: `./scripts/lifecycle/stop.sh`
2. Start with explicit provider: `./scripts/lifecycle/start.sh --provider {provider}`
3. Validate configuration: `OIDC_PROVIDER_NAME={provider} scripts/debug/inspect-config.sh validate`

## Recent Fixes and Improvements (2024-12)

### Critical OIDC Connectivity Fix
**Issue**: OIDC flow failing with "network is unreachable" when accessing Microsoft EntraID
**Root Cause**: APISIX container unable to resolve external DNS for EntraID discovery endpoint
**Solution Applied**:
- Added DNS configuration to APISIX container in `infrastructure/docker/base.yml`
- Added network diagnostic tools to APISIX Dockerfile
- **Status**: ✅ **RESOLVED** - OIDC authentication now works with Microsoft EntraID

```yaml
# Fix applied to infrastructure/docker/base.yml
apisix-dev:
  # ... existing config
  dns:
    - 8.8.8.8
    - 1.1.1.1
```

### Portal Backend Auto-Start Fix
**Issue**: Portal backend service not starting automatically with main services
**Solution Applied**:
- Updated startup script to explicitly include portal-backend service
- **Status**: ✅ **RESOLVED** - Portal backend starts automatically

### Docker Volume Conflict Resolution
**Issue**: Volume conflict errors: "conflicting parameters 'external' and 'driver' specified"
**Solution Applied**:
- Made volume definitions consistent across all Docker Compose files
- Removed obsolete version declarations
- **Status**: ✅ **RESOLVED** - Clean startup/shutdown with no volume errors

### Health Endpoint Optimization
**Issue**: Custom health endpoint `/apisix/status` returning 404
**Solution Applied**:
- Replaced custom health route with APISIX built-in admin API endpoints
- Updated test scripts to use reliable built-in endpoints
- **Status**: ✅ **RESOLVED** - Health checks now use `curl -H "X-API-KEY: $ADMIN_KEY" $APISIX_ADMIN_API/routes`

### Environment Variable Loading Fix
**Issue**: Stop script failing due to missing environment variables
**Solution Applied**:
- Added environment loading to stop script with error handling
- **Status**: ✅ **RESOLVED** - Stop script works reliably

### Verification Commands
After these fixes, the system should work end-to-end:

```bash
# Test full OIDC flow (should show all tests passing)
OIDC_PROVIDER_NAME=entraid scripts/debug/curl-test.sh

# Test health endpoint (should return APISIX routes JSON)
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# Test portal access (should redirect to Microsoft login page)
curl -I http://localhost:9080/portal/

# Test portal backend health
curl http://localhost:3001/health
```

### System Status
**✅ All Critical Issues Resolved**:
- OIDC authentication flow works with Microsoft EntraID
- Portal backend starts automatically
- No Docker volume conflicts
- Health checks use reliable built-in endpoints
- All test scripts pass successfully
- Environment switching works cleanly

## Legacy Files (Archived)

The following files have been moved to `old/` directory:
- Legacy startup scripts (`start-dev.sh`, `start-test.sh`, etc.)
- Legacy environment files (`.dev.env`, `.test.env`, `admin.env`)
- Legacy Docker Compose files (`docker-compose.dev.yml`, `docker-compose.test.yml`)
- Legacy bootstrap scripts and inspection tools

These files are preserved for reference but the new IAC implementation should be used going forward.

## Key Improvements Over Legacy Implementation

### Before (Problems)
- ❌ Mixed provider configurations in single file
- ❌ Placeholder values hardcoded in dev environment
- ❌ No clean provider switching mechanism
- ❌ Limited debugging capabilities
- ❌ Secrets mixed with configuration
- ❌ Tight coupling between components

### After (Solutions)
- ✅ Clean provider separation with dedicated configs
- ✅ Secrets properly separated and gitignored
- ✅ Single command provider switching
- ✅ Enhanced debug containers with curl and network tools
- ✅ Comprehensive validation and testing utilities
- ✅ IAC principles with version-controlled infrastructure
- ✅ Modular architecture with clear separation of concerns

---

This implementation provides a robust, maintainable, and scalable foundation for APISIX Gateway with multi-provider OIDC support following Infrastructure-as-Code best practices.