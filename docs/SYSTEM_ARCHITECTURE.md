# APISIX Gateway System Architecture

**Complete Technical Documentation for Multi-Environment Apache APISIX Setup with Domain Separation**

---

## Table of Contents
- [System Overview](#system-overview)
- [Architecture Components](#architecture-components)
- [Environment Separation](#environment-separation)
- [Domain Routing Architecture](#domain-routing-architecture)
- [APISIX Configuration](#apisix-configuration)
- [Apache Virtual Host Setup](#apache-virtual-host-setup)
- [OIDC Authentication Flow](#oidc-authentication-flow)
- [Infrastructure as Code (IaC)](#infrastructure-as-code-iac)
- [Deployment Procedures](#deployment-procedures)
- [Verification & Testing](#verification--testing)
- [Troubleshooting Guide](#troubleshooting-guide)

---

## System Overview

This system implements a **multi-environment APISIX Gateway** with **domain-based routing** and **Microsoft EntraID OIDC authentication**. The architecture provides complete isolation between development and test environments while maintaining shared Apache reverse proxy infrastructure.

### Key Features
- **Environment Separation**: Independent dev/test APISIX instances with isolated configurations
- **Domain Routing**: `lamassu.ita.chalmers.se` (dev) and `ai-gateway.portal.chalmers.se` (test)
- **OIDC Authentication**: Microsoft EntraID integration with proper header handling
- **Infrastructure as Code**: Fully automated deployment with Docker Compose
- **Security Hardening**: Admin API localhost-only access, proper TLS termination

---

## Architecture Components

### Network Flow Overview
```
Internet → Apache (443/80) → APISIX Gateway → Portal Backend → Services
                ↓
        Domain-Based Routing:
        lamassu.ita.chalmers.se → 127.0.0.1:9080 (Dev APISIX)
        ai-gateway.portal.chalmers.se → 127.0.0.1:9081 (Test APISIX)
```

### Core Services

#### 1. Apache HTTP Server (External Entry Point)
- **Ports**: 80 (HTTP), 443 (HTTPS)
- **Function**: TLS termination, domain-based routing, OIDC header injection
- **Certificates**: Let's Encrypt SSL for both domains

#### 2. APISIX Gateway Instances
- **Dev Instance**: `127.0.0.1:9080` (gateway), `127.0.0.1:9180` (admin)
- **Test Instance**: `127.0.0.1:9081` (gateway), `127.0.0.1:9181` (admin)
- **Function**: API gateway, OIDC authentication, route management

#### 3. Portal Backend Services
- **Dev**: `apisix-dev-portal-backend-1:3000`
- **Test**: `apisix-test-portal-backend-1:3000`
- **Function**: Self-service API key management

#### 4. etcd Configuration Stores
- **Dev**: `apisix-dev-etcd-1:2379`
- **Test**: `apisix-test-etcd-1:2379`
- **Function**: APISIX configuration persistence

---

## Environment Separation

### Docker Compose Projects
The system uses **Docker Compose Projects** for complete environment isolation:

```bash
# Dev Environment
COMPOSE_PROJECT_NAME=apisix-dev

# Test Environment
COMPOSE_PROJECT_NAME=apisix-test
```

### Port Mappings

| Environment | Gateway Port | Admin Port | Purpose |
|------------|-------------|------------|---------|
| Dev        | 9080        | 9180       | Development/staging |
| Test       | 9081        | 9181       | Testing/validation |

### Container Naming Convention
- **Pattern**: `{service}-{environment}`
- **Examples**:
  - `apisix-dev-apisix-1` (dev gateway)
  - `apisix-test-apisix-1` (test gateway)
  - `apisix-dev-portal-backend-1` (dev backend)

---

## Domain Routing Architecture

### Apache Virtual Host Configuration

#### Dev Domain: `lamassu.ita.chalmers.se`
```apache
<VirtualHost *:443>
    ServerName lamassu.ita.chalmers.se

    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/lamassu.ita.chalmers.se/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/lamassu.ita.chalmers.se/privkey.pem

    # OIDC-Compatible Headers
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"
    RequestHeader set X-Forwarded-Host "%{Host}i"

    # Proxy to Dev APISIX (port 9080)
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:9080/
    ProxyPassReverse / http://127.0.0.1:9080/

    # Block Admin API Access (Security)
    <LocationMatch "^/apisix/admin(/.*)?$">
        Require all denied
    </LocationMatch>
</VirtualHost>
```

#### Test Domain: `ai-gateway.portal.chalmers.se`
```apache
<VirtualHost *:443>
    ServerName ai-gateway.portal.chalmers.se

    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/ai-gateway.portal.chalmers.se/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/ai-gateway.portal.chalmers.se/privkey.pem

    # OIDC-Compatible Headers
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"
    RequestHeader set X-Forwarded-Host "%{Host}i"

    # Proxy to Test APISIX (port 9081)
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:9081/
    ProxyPassReverse / http://127.0.0.1:9081/

    # Block Admin API Access (Security)
    <LocationMatch "^/apisix/admin(/.*)?$">
        Require all denied
    </LocationMatch>
</VirtualHost>
```

### Critical Configuration Fixes Applied
1. **ServerAlias Elimination**: Removed cross-wiring between domains
2. **OIDC Header Correction**: Fixed `X-Forwarded-Proto: "https"` (was "http")
3. **Port Separation**: Dev→9080, Test→9081 (was both→9080)
4. **Admin API Blocking**: `LocationMatch` rules return 403 for `/apisix/admin/*`

---

## APISIX Configuration

### Route Categories

#### Core Routes (Always Deployed)
1. **Health Route**: `/health` - System health checks
2. **Portal Routes**: `/portal/*` - Main application interface
3. **OIDC Routes**: Authentication handling
4. **Redirect Routes**: URL normalization

#### Provider Routes (Optional)
1. **Anthropic**: `/v1/providers/anthropic/chat`
2. **OpenAI**: `/v1/providers/openai/chat`
3. **LiteLLM**: `/v1/providers/litellm/chat`

### Example Route Configuration
```json
{
  "id": "portal-oidc-route",
  "uri": "/portal/*",
  "methods": ["GET", "POST", "HEAD"],
  "plugins": {
    "openid-connect": {
      "discovery": "$OIDC_DISCOVERY_ENDPOINT",
      "client_id": "$OIDC_CLIENT_ID",
      "client_secret": "$OIDC_CLIENT_SECRET",
      "redirect_uri": "$OIDC_REDIRECT_URI",
      "session": {
        "secret": "$OIDC_SESSION_SECRET"
      },
      "set_id_token_header": true,
      "set_userinfo_header": true,
      "set_access_token_header": true
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "$PORTAL_BACKEND_HOST": 1
    }
  }
}
```

### Security Configuration
- **Admin API Binding**: `127.0.0.1` only (not `0.0.0.0`)
- **Gateway Binding**: `127.0.0.1` only (behind Apache reverse proxy)
- **HTTPS Enforcement**: Via Apache TLS termination
- **Header Validation**: Proper OIDC-compatible forwarded headers

---

## Apache Virtual Host Setup

### Files Structure
```
/etc/apache2/sites-available/
├── lamassu-ita-chalmers.conf          # Dev domain config
├── ai-gateway-portal-chalmers.conf    # Test domain config
└── (old configs disabled)

/etc/apache2/sites-enabled/
├── lamassu-ita-chalmers.conf -> ../sites-available/lamassu-ita-chalmers.conf
└── ai-gateway-portal-chalmers.conf -> ../sites-available/ai-gateway-portal-chalmers.conf
```

### Required Apache Modules
```bash
a2enmod proxy
a2enmod proxy_http
a2enmod ssl
a2enmod headers
a2enmod rewrite
```

### SSL Certificate Management
```bash
# Lamassu (existing)
/etc/letsencrypt/live/lamassu.ita.chalmers.se/

# AI Gateway (created during Phase 2)
/etc/letsencrypt/live/ai-gateway.portal.chalmers.se/
```

---

## OIDC Authentication Flow

### Microsoft EntraID Integration

#### Configuration Variables
```env
# Dev Environment
OIDC_CLIENT_ID=a8c920fe-3b30-4c77-aef7-17d85a656ea3
OIDC_DISCOVERY_ENDPOINT=https://login.microsoftonline.com/{tenant}/v2.0/.well-known/openid-configuration
OIDC_REDIRECT_URI=http://localhost:9080/portal/callback

# Test Environment (Future Phase 3)
OIDC_CLIENT_ID={separate-test-client-id}
OIDC_REDIRECT_URI=https://ai-gateway.portal.chalmers.se/portal/callback
```

#### Authentication Flow Steps
1. **User Access**: `https://lamassu.ita.chalmers.se/portal/`
2. **Apache Proxy**: Request forwarded to `127.0.0.1:9080/portal/`
3. **APISIX OIDC**: Redirect to EntraID login
4. **User Authentication**: Microsoft EntraID login page
5. **Callback Processing**: EntraID → APISIX callback handler
6. **Header Injection**: APISIX adds user headers:
   - `X-User-Oid`: User object ID
   - `X-User-Name`: Display name
   - `X-User-Email`: Email address
   - `X-Userinfo`: Full user info JSON
   - `X-Id-Token`: OIDC ID token
   - `X-Access-Token`: Access token
7. **Backend Forwarding**: Request sent to portal backend with user context

---

## Infrastructure as Code (IaC)

### Configuration Hierarchy
```
config/
├── shared/                 # Common settings
│   ├── base.env           # Core APISIX settings
│   └── apisix.env         # Admin keys, etcd config
├── providers/             # Provider-specific settings
│   ├── entraid/
│   │   ├── dev.env        # Dev EntraID config
│   │   └── test.env       # Test EntraID config
│   └── keycloak/
│       └── dev.env        # Local Keycloak config
├── env/                   # Docker Compose env files
│   ├── dev.env           # Dev port mappings
│   ├── test.env          # Test port mappings
│   ├── dev.complete.env  # Generated complete config
│   └── test.complete.env # Generated complete config
└── secrets/              # Credentials (gitignored)
    ├── entraid-dev.env   # Dev secrets
    └── entraid-test.env  # Test secrets (Phase 3)
```

### Environment Loading Process
```bash
# 1. Load shared configuration
source config/shared/base.env
source config/shared/apisix.env

# 2. Load secrets (optional)
source secrets/entraid-dev.env

# 3. Load provider configuration
source config/providers/entraid/dev.env

# 4. Generate complete environment file
# Combines all variables into config/env/dev.complete.env

# 5. Export for Docker Compose
export COMPOSE_ENV_FILE=config/env/dev.complete.env
```

### Docker Compose Architecture
```yaml
# Modular compose files
infrastructure/docker/
├── base.yml              # Core services (etcd, apisix, portal)
├── providers.yml         # Provider services (keycloak)
└── debug.yml            # Debug tools (optional)
```

---

## Deployment Procedures

### Complete Clean-Slate Deployment

#### 1. Environment Cleanup
```bash
# Stop all containers
docker compose -f infrastructure/docker/base.yml -p apisix-dev down -v
docker compose -f infrastructure/docker/base.yml -p apisix-test down -v

# Clean up resources
docker container prune -f
docker network prune -f
docker volume prune -f
```

#### 2. Start Environments
```bash
# Start dev environment (9080/9180)
./scripts/lifecycle/start.sh --provider entraid --environment dev

# Start test environment (9081/9181)
./scripts/lifecycle/start.sh --provider entraid --environment test
```

#### 3. Deploy Routes
```bash
# Deploy dev routes
source scripts/core/environment.sh
setup_environment "entraid" "dev"
./scripts/bootstrap/bootstrap-core.sh dev

# Deploy test routes
setup_environment "entraid" "test"
./scripts/bootstrap/bootstrap-core.sh test
```

#### 4. Apache Configuration Deployment
```bash
# Validate configuration
./scripts/deployment/setup-apache-multi-domain.sh preflight

# Deploy Apache configs
sudo ./scripts/deployment/setup-apache-multi-domain.sh deploy

# Issue SSL certificate (if needed)
sudo certbot certonly --webroot -w /var/www/html -d ai-gateway.portal.chalmers.se

# Enable HTTPS
sudo ./scripts/deployment/setup-apache-multi-domain.sh enable-ai-gateway-https

# Verify deployment
./scripts/deployment/setup-apache-multi-domain.sh verify
```

### Command Reference

#### Environment Management
```bash
# Start specific environment
./scripts/lifecycle/start.sh --provider entraid --environment {dev|test}

# Stop environment
./scripts/lifecycle/stop.sh

# Debug mode (adds diagnostic containers)
./scripts/lifecycle/start.sh --provider entraid --environment dev --debug
```

#### Route Deployment
```bash
# Deploy core routes (health, portal, OIDC)
./scripts/bootstrap/bootstrap-core.sh {dev|test}

# Deploy provider routes (AI services)
./scripts/bootstrap/bootstrap-providers.sh {dev|test}
```

#### Apache Management
```bash
# Preflight validation
./scripts/deployment/setup-apache-multi-domain.sh preflight

# Deploy configurations
./scripts/deployment/setup-apache-multi-domain.sh deploy

# Enable HTTPS for ai-gateway
./scripts/deployment/setup-apache-multi-domain.sh enable-ai-gateway-https

# Verify routing separation
./scripts/deployment/setup-apache-multi-domain.sh verify
```

---

## Verification & Testing

### Phase 2 Definition of Done (DoD) Verification

#### 1. SSL Certificate Validation
```bash
# Check lamassu certificate
openssl s_client -connect lamassu.ita.chalmers.se:443 -servername lamassu.ita.chalmers.se </dev/null 2>/dev/null | openssl x509 -noout -subject

# Check ai-gateway certificate
openssl s_client -connect ai-gateway.portal.chalmers.se:443 -servername ai-gateway.portal.chalmers.se </dev/null 2>/dev/null | openssl x509 -noout -subject
```
**Expected**: Both show correct CN matching domain names

#### 2. Apache Virtual Host Configuration
```bash
apache2ctl -S
```
**Expected**: Exactly 2 enabled sites, no ServerAlias cross-wiring

#### 3. Admin API Security (Critical)
```bash
curl -H 'Host: lamassu.ita.chalmers.se' https://lamassu.ita.chalmers.se/apisix/admin/routes
curl -H 'Host: ai-gateway.portal.chalmers.se' https://ai-gateway.portal.chalmers.se/apisix/admin/routes
```
**Expected**: Both return `403 Forbidden`

#### 4. Health Endpoints & Domain Separation
```bash
curl -H 'Host: lamassu.ita.chalmers.se' https://lamassu.ita.chalmers.se/health
curl -H 'Host: ai-gateway.portal.chalmers.se' https://ai-gateway.portal.chalmers.se/health
```
**Expected**: Both return `200 OK` with different responses proving domain separation

#### 5. HEAD Method Support
```bash
curl -I -H 'Host: lamassu.ita.chalmers.se' https://lamassu.ita.chalmers.se/portal/
curl -I -H 'Host: ai-gateway.portal.chalmers.se' https://ai-gateway.portal.chalmers.se/portal/
```
**Expected**: Both return proper HTTP headers without errors

### Service Health Checks
```bash
# Container status
docker ps --filter "name=apisix"

# Port verification
ss -lntp | grep ':90[8-9][0-1]'  # Should show 9080, 9081
ss -lntp | grep ':918[0-1]'      # Should show 9180, 9181

# APISIX admin API
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9181/apisix/admin/routes

# Portal backend health
curl http://localhost:3001/health   # Direct backend access
```

---

## Troubleshooting Guide

### Common Issues & Solutions

#### 1. Bootstrap Route Deployment Failures

**Symptom**: Routes fail to deploy during bootstrap
```
❌ ❌ Failed to deploy portal-redirect-route (HTTP 400)
```

**Causes & Solutions**:
- **Redirect Plugin Schema**: Remove conflicting `http_to_https` and `uri` properties
- **Wrong Portal Backend**: Update hostname from `portal-backend-dev` to `apisix-dev-portal-backend-1`
- **Admin API Access**: Verify admin key and localhost binding

#### 2. Environment Variable Issues

**Symptom**: "Defaulting to a blank string" warnings
```
WARN[0000] The "ADMIN_KEY" variable is not set. Defaulting to a blank string.
```

**Solution**: Use proper environment loading
```bash
source scripts/core/environment.sh
setup_environment "entraid" "dev"
```

#### 3. UID Readonly Variable Error

**Symptom**:
```
/config/env/dev.complete.env: line 12: UID: readonly variable
```

**Solution**: Use `HOST_UID` instead of `UID` in environment files

#### 4. Domain Routing Not Working

**Symptom**: Both domains hit same backend or return wrong responses

**Debugging Steps**:
```bash
# Verify Apache virtual hosts
apache2ctl -S

# Check APISIX port bindings
ss -lntp | grep ':908[01]'

# Test direct APISIX access
curl http://localhost:9080/health  # Should work
curl http://localhost:9081/health  # Should work

# Verify different responses
curl -H 'Host: lamassu.ita.chalmers.se' https://lamassu.ita.chalmers.se/health
curl -H 'Host: ai-gateway.portal.chalmers.se' https://ai-gateway.portal.chalmers.se/health
```

#### 5. OIDC Authentication Issues

**Symptom**: OIDC redirects fail or show errors

**Debugging Steps**:
```bash
# Verify discovery endpoint
curl $OIDC_DISCOVERY_ENDPOINT

# Check redirect URI configuration
echo $OIDC_REDIRECT_URI

# Validate headers in Apache
curl -I https://lamassu.ita.chalmers.se/portal/

# Check APISIX OIDC route
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes/portal-oidc-route
```

### Log Analysis

#### Container Logs
```bash
# APISIX logs
docker logs apisix-dev-apisix-1 -f
docker logs apisix-test-apisix-1 -f

# Portal backend logs
docker logs apisix-dev-portal-backend-1 -f
docker logs apisix-test-portal-backend-1 -f

# Apache logs
sudo tail -f /var/log/apache2/error.log
sudo tail -f /var/log/apache2/access.log
```

#### Debug Mode
```bash
# Start with debug containers
./scripts/lifecycle/start.sh --provider entraid --environment dev --debug

# Access debug toolkit
docker exec -it apisix-debug-toolkit bash

# Access HTTP client
docker exec -it apisix-http-client sh
```

---

## Future Development (Phase 3+)

### Phase 3: Complete Environment Isolation
- [ ] Separate EntraID applications for dev/test
- [ ] Environment-specific OIDC redirect URIs
- [ ] Independent authentication flows
- [ ] Test secrets file (`secrets/entraid-test.env`)

### Phase 4: Operational Excellence
- [ ] Convenience management scripts
- [ ] Automated monitoring and alerting
- [ ] Complete documentation updates
- [ ] Production deployment procedures

---

## Security Considerations

### Current Security Measures
- ✅ Admin API localhost-only binding (`127.0.0.1`)
- ✅ Apache LocationMatch admin API blocking
- ✅ TLS certificate validation
- ✅ OIDC authentication enforcement
- ✅ Proper header forwarding

### Production Hardening Recommendations
- [ ] Rate limiting configuration
- [ ] WAF integration
- [ ] Network segmentation
- [ ] Secrets rotation procedures
- [ ] Audit logging enhancement

---

## Maintenance & Operations

### Regular Maintenance Tasks
1. **SSL Certificate Renewal**: Automated via Certbot
2. **Container Image Updates**: Monitor for security updates
3. **Configuration Backup**: Regular backup of etcd and configuration files
4. **Log Rotation**: Ensure proper log management
5. **Performance Monitoring**: Track response times and error rates

### Change Management
1. **Configuration Changes**: Always use IaC procedures
2. **Route Updates**: Use bootstrap scripts for consistency
3. **Apache Changes**: Use deployment scripts with verification
4. **Testing**: Verify all DoD requirements after changes

---

**Document Version**: 1.0
**Last Updated**: December 17, 2025
**Authors**: Claude Code + Engineering Team
**Review Status**: Phase 2 Complete, Ready for Phase 3

---

This document provides complete technical coverage for maintaining, troubleshooting, and extending the APISIX Gateway multi-environment setup. All procedures have been tested and verified through the Phase 2 implementation.