# Portal Backend Development Guide

## Overview

This guide covers development workflows, setup procedures, testing approaches, and best practices for contributing to the Self-Service API Key Portal Backend.

## Development Environment Setup

### Prerequisites

- **Docker & Docker Compose**: For container orchestration
- **Python 3.11+**: For local development (optional)
- **curl**: For API testing
- **jq**: For JSON processing (optional but recommended)

### Quick Start

1. **Clone and Navigate**:
```bash
git clone <repository>
cd apisix-gateway
```

2. **Configure Secrets** (one-time setup):
```bash
# Copy the template and update with real credentials
cp secrets/entraid-dev.env.template secrets/entraid-dev.env
# Update with actual EntraID credentials from your admin
```

3. **Start Development Environment**:
```bash
# Full stack with EntraID
./scripts/lifecycle/start.sh --provider entraid --debug

# Or with Keycloak for local development
./scripts/lifecycle/start.sh --provider keycloak --debug
```

4. **Verify Setup**:
```bash
# Health checks
curl http://localhost:3001/health
curl http://localhost:9180/apisix/admin/routes -H "X-API-KEY: $ADMIN_KEY"

# Access portal (will redirect to OIDC)
open http://localhost:9080/portal/
```

## Development Workflows

### 1. Full Stack Development (Recommended)

For end-to-end development and testing with complete OIDC flow:

```bash
# Start with debug mode for enhanced tooling
./scripts/lifecycle/start.sh --provider entraid --debug

# Monitor portal backend logs
docker logs -f portal-backend-dev

# Monitor APISIX logs
docker logs -f apisix-dev

# Access services
open http://localhost:9080/portal/    # Portal (OIDC protected)
open http://localhost:9180            # APISIX Admin Dashboard
curl http://localhost:3001/health     # Portal Backend Health
```

### 2. Direct Backend Development

For rapid backend iteration without OIDC flow:

```bash
# Start services
./scripts/lifecycle/start.sh --provider entraid

# Direct backend testing with simulated headers
curl -H "X-User-Oid: dev-user-123" \
     -H "X-User-Name: Dev User" \
     -H "X-User-Email: dev@example.com" \
     http://localhost:3001/portal/

# Test API key operations
curl -X POST \
     -H "X-User-Oid: dev-user-123" \
     -H "Content-Type: application/json" \
     http://localhost:3001/portal/get-key
```

### 3. Local Python Development (Advanced)

For developers who prefer local Python development:

```bash
# Start only infrastructure (without portal-backend)
./scripts/lifecycle/start.sh --provider entraid
docker stop portal-backend-dev

# Set up local Python environment
cd portal-backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Set environment variables
export ADMIN_KEY=$(grep ADMIN_KEY config/shared/apisix.env | cut -d= -f2)
export APISIX_ADMIN_API_CONTAINER=http://localhost:9180/apisix/admin
export ENVIRONMENT=dev

# Run locally
python src/app.py
```

## Portal Backend Architecture

### Code Organization

```
portal-backend/
├── src/
│   └── app.py              # Main Flask application
├── templates/
│   └── dashboard.html      # Portal UI template
├── requirements.txt        # Python dependencies
├── Dockerfile             # Container image definition
└── README.md              # Service-specific documentation
```

### Key Classes and Functions

#### `APIKey` Class
- **Purpose**: Secure API key generation and fingerprinting
- **Methods**:
  - `generate()`: CSPRNG-based key generation using `secrets.token_urlsafe(32)`
  - `get_fingerprint(key)`: Creates safe logging fingerprint `key[:8]...key[-4:]`

#### `APISIXClient` Class
- **Purpose**: APISIX Admin API integration
- **Methods**:
  - `find_consumer(user_oid)`: Locate existing consumer by username
  - `create_consumer(user_oid, user_name, user_email)`: Create new consumer
  - `get_consumer_credentials(user_oid)`: Get existing key-auth credentials
  - `create_credential(user_oid, api_key)`: Add key-auth plugin to consumer
  - `update_credential(user_oid, credential_id, api_key)`: Update existing key-auth

#### `PortalService` Class
- **Purpose**: Business logic orchestration
- **Methods**:
  - `resolve_user_identity(headers)`: Extract user identity from APISIX headers
  - `ensure_consumer_exists(user_identity)`: Create consumer if missing
  - `get_or_create_api_key(user_identity)`: Get key operation logic
  - `recycle_api_key(user_identity)`: Recycle key operation logic

### Configuration Management

Portal backend uses environment variables sourced from the IAC configuration system:

```bash
# Core APISIX integration
ADMIN_KEY                    # APISIX Admin API key
APISIX_ADMIN_API_CONTAINER  # Container-internal Admin API URL
APISIX_ADMIN_API           # External Admin API URL

# Environment context
ENVIRONMENT                 # dev/staging/prod
PORTAL_BACKEND_HOST        # Service hostname for Docker networking
```

## Testing and Quality Assurance

### Unit Testing Strategy

```bash
# Test structure (future implementation)
portal-backend/
├── tests/
│   ├── unit/
│   │   ├── test_apikey.py      # APIKey class tests
│   │   ├── test_apisix_client.py  # APISIXClient tests
│   │   └── test_portal_service.py  # PortalService tests
│   ├── integration/
│   │   ├── test_endpoints.py    # API endpoint tests
│   │   └── test_consumer_flow.py  # Full consumer lifecycle
│   └── fixtures/
│       └── mock_responses.json   # Mock APISIX API responses
```

### Manual Testing Workflows

#### 1. Basic Endpoint Testing
```bash
# Health check
curl http://localhost:3001/health

# Dashboard (requires headers)
curl -H "X-User-Oid: test-user" http://localhost:3001/portal/

# Get key operation
curl -X POST -H "X-User-Oid: test-user" http://localhost:3001/portal/get-key

# Recycle key operation
curl -X POST -H "X-User-Oid: test-user" http://localhost:3001/portal/recycle-key
```

#### 2. Consumer Lifecycle Testing
```bash
# Test new user flow (no existing consumer)
USER_ID="new-user-$(date +%s)"
curl -X POST -H "X-User-Oid: $USER_ID" http://localhost:3001/portal/get-key

# Verify consumer creation in APISIX
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/consumers/$USER_ID

# Test key recycling
curl -X POST -H "X-User-Oid: $USER_ID" http://localhost:3001/portal/recycle-key

# Verify key updated in APISIX
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/consumers/$USER_ID
```

#### 3. Error Condition Testing
```bash
# Missing authentication header
curl -X POST http://localhost:3001/portal/get-key

# Invalid user OID
curl -X POST -H "X-User-Oid: " http://localhost:3001/portal/get-key

# APISIX connectivity (with APISIX stopped)
docker stop apisix-dev
curl -X POST -H "X-User-Oid: test-user" http://localhost:3001/portal/get-key
```

### Integration Testing

#### End-to-End OIDC Flow Testing
```bash
# Start full environment
./scripts/lifecycle/start.sh --provider entraid

# Manual browser testing
open http://localhost:9080/portal/
# 1. Should redirect to EntraID/Keycloak
# 2. After login, should show portal dashboard
# 3. Key operations should work through UI

# Automated flow testing
scripts/debug/curl-test.sh portal
```

## Development Best Practices

### Code Style and Standards

1. **Python Style**: Follow PEP 8 with these specifics:
   - Line length: 100 characters
   - Use type hints for function signatures
   - Docstrings for all classes and public methods

2. **Security Guidelines**:
   - Never log full API keys - use `APIKey.get_fingerprint()`
   - Validate all user inputs, especially headers
   - Use `secrets` module for cryptographic operations
   - Sanitize user data in log messages

3. **Error Handling**:
   - Catch specific exceptions rather than broad `Exception`
   - Provide meaningful error messages to users
   - Log detailed technical information for debugging
   - Return appropriate HTTP status codes

### Logging Best Practices

#### What to Log
```python
# Good: Operation with user identification
logger.info(f"Created consumer for user_oid: {user_oid}, name: {user_name}")

# Good: Key operation with fingerprint
key_fingerprint = APIKey.get_fingerprint(api_key)
logger.info(f"Generated new API key for user_oid: {user_oid}, key_fingerprint: {key_fingerprint}")

# Good: Technical errors with context
logger.error(f"APISIX API request failed: {method} {url} - {e}")
```

#### What NOT to Log
```python
# Bad: Full API key
logger.info(f"Generated key: {api_key}")  # NEVER DO THIS

# Bad: Sensitive headers or secrets
logger.info(f"Request headers: {dict(request.headers)}")  # Contains secrets

# Bad: Full user identity in error logs
logger.error(f"Failed for user: {user_identity}")  # Contains PII
```

### Environment Variables Management

#### Required Variables
```bash
# Always required
ADMIN_KEY                    # From config/shared/apisix.env
APISIX_ADMIN_API_CONTAINER  # From config/shared/base.env

# Optional with defaults
ENVIRONMENT=dev             # Defaults to 'dev'
PORTAL_BACKEND_HOST         # Defaults to 'portal-backend:3000'
```

#### Local Development Overrides
```bash
# For local Python development
export APISIX_ADMIN_API_CONTAINER=http://localhost:9180/apisix/admin
export APISIX_ADMIN_API=http://localhost:9180/apisix/admin
```

## Debugging and Troubleshooting

### Common Development Issues

#### 1. "Authentication required" Errors
**Symptoms**: 401 errors when testing endpoints
**Solution**: Always include `X-User-Oid` header in direct backend testing:
```bash
curl -H "X-User-Oid: test-user-123" http://localhost:3001/portal/
```

#### 2. APISIX Connection Failures
**Symptoms**: "Failed to get API key" with connection errors
**Debug Steps**:
```bash
# Check if APISIX is running
docker ps | grep apisix-dev

# Test connectivity from portal backend
docker exec portal-backend-dev curl -v http://apisix-dev:9180/apisix/admin/routes

# Verify ADMIN_KEY is set correctly
docker exec portal-backend-dev printenv ADMIN_KEY
```

#### 3. Consumer Creation Failures
**Symptoms**: Consumer API returns 400/500 errors
**Debug Steps**:
```bash
# Check ETCD health
docker exec etcd-dev etcdctl endpoint health

# Test Consumer API manually
curl -X PUT -H "X-API-KEY: $ADMIN_KEY" \
     -H "Content-Type: application/json" \
     -d '{"username":"debug-test","desc":"debug consumer"}' \
     http://localhost:9180/apisix/admin/consumers/debug-test

# Check for forbidden ETCD fields in update payloads
docker logs portal-backend-dev | grep -i "forbidden"
```

#### 4. Template/UI Issues
**Symptoms**: Portal dashboard not rendering correctly
**Debug Steps**:
```bash
# Check if template file exists in container
docker exec portal-backend-dev ls -la templates/

# Test template rendering with curl
curl -H "X-User-Oid: test-user" http://localhost:3001/portal/ | head -20

# Check Flask template path configuration
docker exec portal-backend-dev python -c "
from src.app import app
print('Template folder:', app.template_folder)
"
```

### Debugging Tools and Commands

#### Container Inspection
```bash
# Portal backend container shell
docker exec -it portal-backend-dev bash

# Check environment variables
docker exec portal-backend-dev env | grep -E "(ADMIN|APISIX|PORTAL)"

# Check network connectivity
docker exec portal-backend-dev ping apisix-dev
docker exec portal-backend-dev curl -v http://apisix-dev:9180/health
```

#### Log Analysis
```bash
# Real-time logs with timestamp
docker logs -f -t portal-backend-dev

# Filter for errors only
docker logs portal-backend-dev 2>&1 | grep -i error

# Search for specific user operations
docker logs portal-backend-dev 2>&1 | grep "user_oid: test-user"

# API key operations (will show fingerprints only)
docker logs portal-backend-dev 2>&1 | grep "key_fingerprint"
```

#### Network and Connectivity Testing
```bash
# Test from debug container
docker exec -it apisix-debug-toolkit bash
curl -v http://portal-backend:3000/health
curl -H "X-User-Oid: debug-user" http://portal-backend:3000/portal/

# Test APISIX Admin API from outside
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes | jq .

# Test portal access through APISIX
curl -v http://localhost:9080/portal/
```

## Contributing Guidelines

### Code Changes Workflow

1. **Branch Creation**:
```bash
git checkout -b feature/portal-enhancement-description
```

2. **Development**:
   - Make changes following code style guidelines
   - Add appropriate logging and error handling
   - Test manually using workflows described above

3. **Testing Checklist**:
   - [ ] Health endpoint responds correctly
   - [ ] Dashboard loads with valid headers
   - [ ] Get key operation works for new and existing users
   - [ ] Recycle key operation works correctly
   - [ ] Error conditions return appropriate HTTP codes
   - [ ] No sensitive data appears in logs
   - [ ] Container builds successfully
   - [ ] Full OIDC flow works end-to-end

4. **Commit and PR**:
```bash
git add .
git commit -m "Add specific description of changes"
git push origin feature/portal-enhancement-description
# Create PR with description of changes and testing performed
```

### Documentation Updates

When making changes, update relevant documentation:
- **README.md**: For architectural or setup changes
- **docs/API.md**: For endpoint or response format changes
- **docs/PORTAL_DEVELOPMENT.md**: For development workflow changes
- **Code comments**: For complex business logic changes

### Performance Considerations

- **APISIX API Calls**: Minimize API calls by caching consumer lookups where appropriate
- **Error Handling**: Fail fast on missing headers rather than continuing processing
- **Logging**: Use appropriate log levels to avoid excessive DEBUG output in production
- **Memory Usage**: Avoid storing API keys in memory longer than necessary

---

This development guide provides the foundation for productive portal backend development. For additional questions or clarification, refer to the main README.md or create an issue in the project repository.