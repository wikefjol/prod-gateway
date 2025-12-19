# APISIX Gateway Maintainers Guide

A comprehensive technical guide for maintainers of the APISIX Gateway with Multi-Provider OIDC system.

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Configuration Management](#configuration-management)
3. [Deployment & Operations](#deployment--operations)
4. [Security Management](#security-management)
5. [Troubleshooting & Debugging](#troubleshooting--debugging)
6. [Maintenance Procedures](#maintenance-procedures)
7. [Development Workflows](#development-workflows)
8. [Monitoring & Logging](#monitoring--logging)
9. [Emergency Procedures](#emergency-procedures)
10. [Updates & Upgrades](#updates--upgrades)

---

## System Architecture

### High-Level Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   External      │    │   APISIX         │    │   Backend       │
│   Clients       │───▶│   Gateway        │───▶│   Services      │
│                 │    │   (Port 9080)    │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │   OIDC Provider  │
                       │   (EntraID/      │
                       │    Keycloak)     │
                       └──────────────────┘
```

### Container Architecture

| Container | Purpose | Ports | Network Access |
|-----------|---------|-------|----------------|
| `apisix-dev` | Main API Gateway | 9080 (public), 9180 (localhost-only) | External, Internal |
| `etcd-dev` | APISIX Configuration Store | 2379 (internal) | Internal only |
| `portal-backend-dev` | Self-Service Portal | 3000 (internal), 3001 (external) | Internal, External |
| `keycloak-dev` | Local OIDC Provider | 8080 (conditional) | External (dev only) |

### Network Security Model

```
External Access (0.0.0.0):
├── Port 9080 (APISIX Gateway) ✅ SAFE
│   ├── OIDC-protected routes
│   ├── API key-protected routes
│   └── Public health endpoints
└── Port 3001 (Portal Backend) ✅ SAFE
    └── Direct access bypasses OIDC (dev only)

Localhost Access (127.0.0.1):
└── Port 9180 (APISIX Admin) 🔒 ADMIN ONLY
    └── Full APISIX control interface

Internal Only (Container Network):
├── Port 2379 (etcd)
├── Port 3000 (Portal Backend Internal)
└── Port 8080 (Keycloak, conditional)
```

## Configuration Management

### Configuration Hierarchy

The system uses a three-tier configuration hierarchy:

1. **Shared Configuration** (`config/shared/`)
   - `base.env`: Core APISIX settings
   - `apisix.env`: Admin keys and core configuration

2. **Secrets** (`secrets/{provider}-{environment}.env`)
   - OIDC client credentials
   - API provider keys
   - Session secrets
   - **Status**: Gitignored, managed by administrators

3. **Provider Configuration** (`config/providers/{provider}/`)
   - Provider-specific OIDC settings
   - Environment-specific overrides

### Critical Configuration Files

#### `/home/filbern/dev/apisix-gateway/apisix/config-dev-template.yaml`
**Purpose**: APISIX plugin and core configuration template
**Processing**: Environment variables substituted via `envsubst`
**Critical Sections**:
```yaml
plugins:
  - proxy-rewrite
  - limit-count
  - cors
  - key-auth
  - hmac-auth
  - openid-connect
  - consumer-restriction
  - redirect                    # UX redirects
  - serverless-pre-function     # Custom responses
```

#### `secrets/entraid-dev.env`
**Purpose**: Microsoft EntraID credentials (production)
**Security**: High - contains OAuth client secrets
**Example Structure**:
```bash
ENTRAID_CLIENT_ID=your-application-client-id
ENTRAID_CLIENT_SECRET=your-client-secret-value
ENTRAID_TENANT_ID=your-azure-tenant-id
ENTRAID_SESSION_SECRET=$(openssl rand -hex 16)
```

#### `config/providers/entraid/dev.env`
**Purpose**: EntraID-specific configuration
**Contents**: Discovery URLs, redirect URIs, scopes

### Environment Variable Loading

The `scripts/core/environment.sh` script implements hierarchical loading:

```bash
setup_environment() {
    local provider="$1"
    local environment="$2"

    # 1. Load shared configuration
    load_shared_config

    # 2. Load secrets (critical for credentials)
    load_secrets "$provider" "$environment"

    # 3. Load provider-specific configuration
    load_provider_config "$provider" "$environment"

    # 4. Generate computed values
    generate_dynamic_values

    # 5. Validate required variables
    validate_environment
}
```

## Deployment & Operations

### Standard Deployment Procedure

#### 1. Pre-Deployment Checklist
- [ ] Verify all secrets files exist and contain non-placeholder values
- [ ] Validate network connectivity to OIDC provider
- [ ] Ensure Docker and Docker Compose are updated
- [ ] Backup current etcd data if preserving state is critical

#### 2. Deployment Commands

**Clean Deployment** (recommended for production):
```bash
# Stop existing services
./scripts/lifecycle/stop.sh

# Start with specific provider
./scripts/lifecycle/start.sh --provider entraid

# Validate deployment
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh validate
```

**Debug Deployment** (for troubleshooting):
```bash
./scripts/lifecycle/start.sh --provider entraid --debug
```

#### 3. Post-Deployment Validation

**System Health Checks**:
```bash
# Verify all containers running
docker compose ps

# Test UX routes
curl -I http://localhost:9080/                    # → 302 to /portal/
curl -I http://localhost:9080/portal             # → 302 to /portal/
curl http://localhost:9080/health                # → 200 JSON

# Test OIDC flow
curl -v http://localhost:9080/portal/             # → 302 to OIDC provider

# Verify admin API (localhost only)
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# Test portal backend
curl http://localhost:3001/health
```

### Container Lifecycle Management

#### Service Dependencies
```
etcd-dev (first)
  ↓
apisix-dev (depends on etcd)
  ↓
portal-backend-dev (depends on apisix)
  ↓
apisix-loader-dev (bootstrap, depends on apisix)
```

#### Container Restart Procedures

**Graceful Restart**:
```bash
./scripts/lifecycle/stop.sh
./scripts/lifecycle/start.sh --provider {current-provider}
```

**Force Rebuild** (when configuration changes):
```bash
./scripts/lifecycle/stop.sh
docker system prune -f  # Optional: clean up old images
./scripts/lifecycle/start.sh --provider {provider} --force-recreate
```

**Individual Container Restart**:
```bash
# Restart specific service (advanced)
docker compose -f infrastructure/docker/base.yml restart apisix-dev
docker compose -f infrastructure/docker/base.yml restart portal-backend-dev
```

## Security Management

### Security Model

#### Authentication Layers
1. **Portal Access**: OIDC authentication (EntraID/Keycloak)
2. **API Access**: API key authentication via APISIX `key-auth` plugin
3. **Admin Access**: Admin API key + localhost binding

#### API Key Management
```bash
# Consumer and credential management through Portal Backend
# 1:1 mapping: OIDC User ↔ APISIX Consumer ↔ API Key

# Manual consumer inspection
curl -H "X-API-KEY: $ADMIN_KEY" \
  http://localhost:9180/apisix/admin/consumers

# Manual credential inspection
curl -H "X-API-KEY: $ADMIN_KEY" \
  http://localhost:9180/apisix/admin/consumers/{user-oid}/credentials
```

### Critical Security Configurations

#### Admin API Security
**Configuration**: `infrastructure/docker/base.yml`
```yaml
apisix-dev:
  ports:
    - "9080:9080"          # Gateway (external safe)
    - "127.0.0.1:9180:9180" # Admin API (localhost only) 🔒
```

**Verification**:
```bash
# Should work (localhost)
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# Should fail (external - replace with your external IP)
curl -H "X-API-KEY: $ADMIN_KEY" http://YOUR-EXTERNAL-IP:9180/apisix/admin/routes
```

#### Secret Management Best Practices

1. **Secrets Separation**: All credentials in `secrets/` directory (gitignored)
2. **Key Rotation**: API keys can be recycled through Portal Backend
3. **Session Security**: OIDC session secrets are environment-specific
4. **Logging**: Full API keys never logged (only fingerprints: `key[:8]...key[-4:]`)

### Security Hardening Checklist

- [ ] Admin API bound to localhost only (`127.0.0.1:9180`)
- [ ] Secrets separated from version control (`.gitignore` updated)
- [ ] API keys use CSPRNG generation (`secrets.token_urlsafe(32)`)
- [ ] OIDC client secrets properly configured for provider
- [ ] No placeholder values in production secrets files
- [ ] Session secrets unique per environment
- [ ] Rate limiting configured (via `limit-count` plugin)

## Troubleshooting & Debugging

### Common Issues and Solutions

#### Issue: OIDC Authentication Failing
**Symptoms**: Portal redirects fail, "network unreachable" errors
**Diagnosis**:
```bash
# Test OIDC discovery endpoint accessibility
OIDC_PROVIDER_NAME=entraid scripts/debug/curl-test.sh discovery

# Verify APISIX can resolve external DNS
docker exec -it apisix-dev nslookup login.microsoftonline.com
```
**Solution**: Verify DNS configuration in APISIX container, check firewall rules

#### Issue: Admin API Returning 404/401
**Symptoms**: Admin API requests fail, missing routes
**Diagnosis**:
```bash
# Verify admin API accessibility
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/schema/plugins

# Check ADMIN_KEY value
echo "ADMIN_KEY: ${ADMIN_KEY:-'NOT SET'}"

# Verify etcd connectivity
docker exec etcd-dev etcdctl endpoint health
```
**Solution**: Reload environment variables, restart services, verify etcd health

#### Issue: Portal Backend Connection Failed
**Symptoms**: Portal shows "Internal server error", credential operations fail
**Diagnosis**:
```bash
# Test portal backend health
curl http://localhost:3001/health

# Test APISIX admin API from portal backend
docker exec portal-backend-dev curl -H "X-API-KEY: $ADMIN_KEY" \
  http://apisix-dev:9180/apisix/admin/consumers

# Check portal backend logs
docker logs portal-backend-dev --tail 20
```
**Solution**: Verify APISIX admin API connectivity, check ADMIN_KEY configuration

#### Issue: UX Routes Not Working
**Symptoms**: Redirects fail, 404 responses use default format
**Diagnosis**:
```bash
# Verify plugins are enabled
curl -H "X-API-KEY: $ADMIN_KEY" \
  http://localhost:9180/apisix/admin/schema/plugins/redirect

# Check route configuration
curl -H "X-API-KEY: $ADMIN_KEY" \
  http://localhost:9180/apisix/admin/routes | jq '.list.list[] | {id: .id, uri: .uri}'

# Test individual routes
curl -I http://localhost:9080/                   # Should be 302
curl -I http://localhost:9080/portal            # Should be 302
curl http://localhost:9080/health               # Should be 200
```
**Solution**: Verify plugins enabled in `config-dev-template.yaml`, restart services

### Debug Mode Operations

#### Enabling Debug Mode
```bash
./scripts/lifecycle/start.sh --provider entraid --debug
```

**Provides**:
- `apisix-debug-toolkit`: Container with curl, jq, network tools
- `apisix-http-client`: Lightweight HTTP testing container
- Enhanced logging and diagnostic capabilities

#### Debug Container Usage
```bash
# Access debug toolkit
docker exec -it apisix-debug-toolkit bash

# Inside debug container - test OIDC endpoints
curl -s "$OIDC_DISCOVERY_ENDPOINT" | jq .

# Test internal connectivity
curl -H "X-API-KEY: $ADMIN_KEY" http://apisix-dev:9180/apisix/admin/routes
```

### Logging and Diagnostics

#### Container Logs
```bash
# APISIX Gateway logs
docker logs apisix-dev --tail 50 -f

# Portal Backend logs
docker logs portal-backend-dev --tail 50 -f

# etcd logs
docker logs etcd-dev --tail 20

# Bootstrap/loader logs
docker logs apisix-loader-dev
```

#### Configuration Inspection
```bash
# Full configuration validation
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh validate

# Network connectivity testing
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh network

# OIDC-specific configuration
OIDC_PROVIDER_NAME=entraid scripts/debug/inspect-config.sh oidc
```

## Maintenance Procedures

### Regular Maintenance Tasks

#### Weekly Tasks
- [ ] Review container logs for errors or warnings
- [ ] Verify all services are healthy using health endpoints
- [ ] Test OIDC authentication flow
- [ ] Check disk usage for Docker volumes
- [ ] Validate SSL certificate expiration dates (if using HTTPS)

#### Monthly Tasks
- [ ] Review and rotate OIDC session secrets if needed
- [ ] Update Docker images and containers
- [ ] Review consumer and credential counts
- [ ] Backup etcd configuration data
- [ ] Test disaster recovery procedures

#### Quarterly Tasks
- [ ] Review and update OIDC provider configurations
- [ ] Security audit of exposed endpoints
- [ ] Performance testing and optimization
- [ ] Documentation updates
- [ ] Penetration testing (if applicable)

### Backup and Recovery

#### Critical Data
1. **etcd Data**: Contains all APISIX route and consumer configurations
2. **Secrets Files**: OIDC credentials, admin keys, session secrets
3. **Configuration Templates**: Custom route definitions and plugin configs

#### Backup Procedure
```bash
# Backup etcd data
docker exec etcd-dev etcdctl snapshot save /tmp/etcd-backup.db
docker cp etcd-dev:/tmp/etcd-backup.db ./backups/etcd-$(date +%Y%m%d).db

# Backup secrets (encrypt before storing)
tar -czf backups/secrets-$(date +%Y%m%d).tar.gz secrets/

# Backup custom configurations
tar -czf backups/config-$(date +%Y%m%d).tar.gz apisix/ config/
```

#### Recovery Procedure
```bash
# Stop services
./scripts/lifecycle/stop.sh

# Restore etcd data (example)
docker run --rm -v etcd_data:/etcd-data -v $(pwd)/backups:/backup \
  quay.io/coreos/etcd:v3.5.0 \
  etcdctl snapshot restore /backup/etcd-20241215.db \
  --data-dir /etcd-data

# Restore secrets and configurations
tar -xzf backups/secrets-20241215.tar.gz
tar -xzf backups/config-20241215.tar.gz

# Restart services
./scripts/lifecycle/start.sh --provider entraid
```

## Development Workflows

### Local Development Setup

#### Developer Environment
```bash
# 1. Start with Keycloak for local development
./scripts/lifecycle/start.sh --provider keycloak --debug

# 2. Access Keycloak admin (admin/admin)
open http://localhost:8080

# 3. Test portal through APISIX
open http://localhost:9080/portal/

# 4. Direct portal backend development
curl -H "X-User-Oid: dev-user" http://localhost:3001/portal/
```

#### Testing New Configurations

**Route Testing**:
```bash
# Create test route
curl -X POST -H "X-API-KEY: $ADMIN_KEY" -H "Content-Type: application/json" \
  -d '{"uri":"/test","plugins":{"proxy-rewrite":{"uri":"/health"}}}' \
  http://localhost:9180/apisix/admin/routes

# Test route
curl http://localhost:9080/test

# Delete test route
curl -X DELETE -H "X-API-KEY: $ADMIN_KEY" \
  http://localhost:9180/apisix/admin/routes/test-route-id
```

**Plugin Testing**:
```bash
# Verify plugin availability
curl -H "X-API-KEY: $ADMIN_KEY" \
  http://localhost:9180/apisix/admin/schema/plugins/your-plugin
```

### Code Review Guidelines

#### Configuration Changes
- [ ] Secrets not committed to version control
- [ ] Environment variables follow naming conventions
- [ ] Configuration templates use proper variable substitution
- [ ] Changes tested in both Keycloak and EntraID modes

#### Security Review
- [ ] No hardcoded credentials
- [ ] Admin API remains localhost-bound
- [ ] New endpoints properly authenticated
- [ ] Rate limiting configured for new routes

#### Documentation Updates
- [ ] README.md updated for new features
- [ ] CLAUDE.md updated with configuration patterns
- [ ] This maintainers guide updated with new procedures

## Monitoring & Logging

### Health Monitoring

#### Automated Health Checks
```bash
#!/bin/bash
# Simple health monitoring script

# APISIX Gateway
curl -f -s http://localhost:9080/health > /dev/null && echo "✅ Gateway" || echo "❌ Gateway"

# Portal Backend
curl -f -s http://localhost:3001/health > /dev/null && echo "✅ Portal" || echo "❌ Portal"

# APISIX Admin (with auth)
curl -f -s -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes > /dev/null && echo "✅ Admin" || echo "❌ Admin"

# Container Status
docker compose ps --format "table {{.Name}}\t{{.Status}}"
```

#### Key Metrics to Monitor
- Container health status
- OIDC authentication success/failure rates
- API key usage patterns
- Response times for critical endpoints
- Error rates in APISIX and portal backend logs

### Log Management

#### Log Locations
```bash
# Container logs (Docker manages rotation)
docker logs apisix-dev
docker logs portal-backend-dev
docker logs etcd-dev

# APISIX internal logs (inside container)
docker exec apisix-dev tail -f /usr/local/apisix/logs/error.log
docker exec apisix-dev tail -f /usr/local/apisix/logs/access.log
```

#### Critical Log Events to Monitor
- `failed to check token` (admin API unauthorized access attempts)
- `Consumer creation failed` (portal backend issues)
- `OIDC discovery failed` (provider connectivity issues)
- HTTP 5xx errors in access logs
- etcd connection failures

## Emergency Procedures

### Service Outage Response

#### Immediate Response (< 5 minutes)
1. **Assess Impact**: Determine which services are affected
2. **Check Health**: Use health endpoints to verify service status
3. **Review Logs**: Check recent logs for error patterns
4. **Quick Restart**: Use lifecycle scripts for rapid restart

```bash
# Emergency restart procedure
./scripts/lifecycle/stop.sh
./scripts/lifecycle/start.sh --provider {current-provider}
```

#### Escalated Response (5-15 minutes)
1. **Isolate Issue**: Determine if it's container, configuration, or infrastructure
2. **Rollback**: If recent changes, rollback to last known good state
3. **Debug Mode**: Enable debug containers for deeper investigation

```bash
# Enable debug mode for investigation
./scripts/lifecycle/start.sh --provider {provider} --debug
```

### Security Incident Response

#### Suspected Admin API Compromise
1. **Immediate**: Stop all services to prevent further access
2. **Assess**: Review admin API access logs for suspicious activity
3. **Rotate**: Generate new admin keys in `config/shared/apisix.env`
4. **Restart**: Deploy with new keys and monitor

#### OIDC Token Compromise
1. **Contact Provider**: Report to OIDC provider (Microsoft/Keycloak admin)
2. **Rotate Secrets**: Update client secrets in `secrets/{provider}-dev.env`
3. **Invalidate Sessions**: Restart services to invalidate active sessions
4. **Monitor**: Watch for suspicious authentication patterns

### Data Recovery Scenarios

#### etcd Data Corruption
```bash
# Stop services
./scripts/lifecycle/stop.sh

# Remove corrupted data
docker volume rm apisix-gateway_etcd_data

# Restore from backup (if available)
# [Follow backup recovery procedure above]

# Otherwise, restart fresh (will lose consumer data)
./scripts/lifecycle/start.sh --provider {provider}
```

#### Configuration File Corruption
```bash
# Restore from version control
git checkout HEAD -- apisix/ config/

# Or restore from backup
tar -xzf backups/config-{date}.tar.gz

# Restart services
./scripts/lifecycle/start.sh --provider {provider}
```

## Updates & Upgrades

### Docker Image Updates

#### APISIX Updates
```bash
# Check current version
docker exec apisix-dev apisix version

# Update procedure
./scripts/lifecycle/stop.sh
docker pull apache/apisix:latest
./scripts/lifecycle/start.sh --provider {provider}
```

#### Portal Backend Updates
```bash
# Rebuild portal backend image
docker compose -f infrastructure/docker/base.yml build --no-cache portal-backend-dev
./scripts/lifecycle/start.sh --provider {provider}
```

### System Updates

#### Operating System Updates
1. Schedule maintenance window
2. Stop APISIX services
3. Update host OS
4. Reboot if required
5. Restart services and validate

#### Plugin Updates
1. Review new plugin documentation
2. Test in development environment
3. Update `config-dev-template.yaml`
4. Deploy with lifecycle scripts
5. Validate functionality

### Configuration Schema Changes

When APISIX or plugin schemas change:

1. **Backup Current Configuration**:
```bash
tar -czf backups/pre-upgrade-$(date +%Y%m%d).tar.gz apisix/ config/
```

2. **Update Templates**: Modify configuration files to match new schema
3. **Test Validation**: Use debug tools to validate configuration
4. **Deploy**: Use lifecycle scripts for controlled deployment
5. **Rollback Plan**: Keep backup available for quick rollback

---

## Emergency Contact Information

### System Access
- **APISIX Gateway**: http://localhost:9080
- **APISIX Admin**: http://localhost:9180 (localhost only)
- **Portal Backend**: http://localhost:3001

### Key Files for Emergency Reference
- `scripts/lifecycle/start.sh` - Emergency startup
- `scripts/lifecycle/stop.sh` - Emergency shutdown
- `secrets/entraid-dev.env` - Production OIDC credentials
- `apisix/config-dev-template.yaml` - Core APISIX configuration
- `CLAUDE.md` - Technical implementation details

### Escalation Procedures
1. **Level 1**: Use this guide for standard troubleshooting
2. **Level 2**: Engage development team with log files and configuration details
3. **Level 3**: Contact infrastructure team with backup and recovery requirements

---

*This guide is maintained alongside the system. Update this document when making configuration or architectural changes.*