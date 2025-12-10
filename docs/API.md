# Portal Backend API Documentation

## Overview

The Portal Backend API provides self-service API key management functionality for APISIX Gateway users. The API follows RESTful principles and integrates with APISIX's Consumer and Credential management system.

**Base URL**: `http://localhost:3001` (development)
**Authentication**: APISIX header injection (OIDC-based)
**Content-Type**: `application/json`

## Authentication

All endpoints (except `/health`) require APISIX-injected user identity headers from successful OIDC authentication:

| Header | Required | Description | Example |
|--------|----------|-------------|---------|
| `X-User-Oid` | Yes | OIDC User Object Identifier | `user123@tenant.onmicrosoft.com` |
| `X-User-Name` | No | User display name | `John Doe` |
| `X-User-Email` | No | User email address | `john.doe@company.com` |

### Authentication Flow
1. User navigates to `http://localhost:9080/portal/`
2. APISIX redirects to OIDC provider (EntraID/Keycloak)
3. After successful authentication, APISIX injects user headers
4. Portal backend validates `X-User-Oid` header for all protected endpoints

## Endpoints

### Health Check

#### `GET /health`

Health check endpoint for container orchestration and monitoring.

**Authentication**: None required

**Request**:
```http
GET /health HTTP/1.1
Host: localhost:3001
```

**Response**:
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
    "status": "healthy",
    "service": "portal-backend"
}
```

**Status Codes**:
- `200`: Service is healthy
- `500`: Service is unhealthy

---

### Portal Dashboard

#### `GET /portal/` and `GET /portal`

Returns the portal dashboard interface showing current API key status.

**Authentication**: Required (`X-User-Oid`)

**Request**:
```http
GET /portal/ HTTP/1.1
Host: localhost:3001
X-User-Oid: user123@tenant.onmicrosoft.com
X-User-Name: John Doe
X-User-Email: john.doe@company.com
```

**Response** (HTML):
```http
HTTP/1.1 200 OK
Content-Type: text/html

<!DOCTYPE html>
<html>
<!-- Portal dashboard HTML with current API key status -->
</html>
```

**Response Variables Passed to Template**:
```javascript
{
    "user_identity": {
        "user_oid": "user123@tenant.onmicrosoft.com",
        "user_name": "John Doe",
        "user_email": "john.doe@company.com"
    },
    "has_key": true,
    "current_key": "abcd1234-example-key-xyz9"  // Only if has_key=true
}
```

**Error Responses**:
```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
    "error": "Authentication required",
    "details": "Missing X-User-Oid header - user not authenticated"
}
```

```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{
    "error": "Internal server error"
}
```

---

### Get API Key

#### `POST /portal/get-key`

Retrieves existing API key or creates a new one following the "Get key" operation specification.

**Authentication**: Required (`X-User-Oid`)

**Business Logic**:
- If exactly 1 credential exists: return existing key
- If 0 credentials exist: generate new key and create credential
- Enforces exactly 0 or 1 key-auth credential per user

**Request**:
```http
POST /portal/get-key HTTP/1.1
Host: localhost:3001
Content-Type: application/json
X-User-Oid: user123@tenant.onmicrosoft.com
X-User-Name: John Doe
X-User-Email: john.doe@company.com
```

**Successful Response** (existing key):
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
    "success": true,
    "api_key": "abcd1234-existing-key-xyz9",
    "message": "API key retrieved successfully"
}
```

**Successful Response** (new key created):
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
    "success": true,
    "api_key": "wxyz5678-new-key-abcd1234",
    "message": "API key retrieved successfully"
}
```

**Error Responses**:
```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
    "error": "Authentication required",
    "details": "Missing X-User-Oid header - user not authenticated"
}
```

```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{
    "error": "Failed to get API key",
    "details": "APISIX Admin API connection failed"
}
```

```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{
    "error": "Failed to get API key",
    "details": "Unexpected number of credentials: 2"
}
```

---

### Recycle API Key

#### `POST /portal/recycle-key`

Rotates/recycles the API key following the "Recycle key" operation specification.

**Authentication**: Required (`X-User-Oid`)

**Business Logic**:
- If 0 credentials exist: treat as "Get key" operation (create new)
- If 1 credential exists: generate new key and update credential
- Previous key becomes immediately invalid after successful update

**Request**:
```http
POST /portal/recycle-key HTTP/1.1
Host: localhost:3001
Content-Type: application/json
X-User-Oid: user123@tenant.onmicrosoft.com
X-User-Name: John Doe
X-User-Email: john.doe@company.com
```

**Successful Response**:
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
    "success": true,
    "api_key": "mnop9012-recycled-key-efgh5678",
    "message": "API key recycled successfully - previous key is now invalid"
}
```

**Error Responses**:
```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
    "error": "Authentication required",
    "details": "Missing X-User-Oid header - user not authenticated"
}
```

```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{
    "error": "Failed to recycle API key",
    "details": "Consumer update failed - forbidden property: create_time"
}
```

## Consumer Management

The Portal Backend automatically manages APISIX Consumers with the following mapping:

### Consumer Creation
- **Trigger**: First portal access or key operation
- **Username**: Uses OIDC `user_oid` as Consumer username
- **Description**: `"Created by SSO portal for {user_name} ({user_email})"`
- **Labels**:
  ```json
  {
    "source": "oidc-portal-v0",
    "created_at": "2025-12-09T10:30:00.000000"
  }
  ```

### Credential Management
- **Method**: Consumer `plugins.key-auth` configuration (not separate Credential API)
- **Key Format**: 32 bytes of CSPRNG randomness encoded as base64url string
- **Example**: `"wxyz5678-new-key-abcd1234"`

### APISIX Admin API Integration

The Portal Backend makes the following calls to APISIX Admin API:

#### Find Consumer
```http
GET /apisix/admin/consumers/{user_oid}
X-API-KEY: {ADMIN_KEY}
```

#### Create Consumer
```http
PUT /apisix/admin/consumers/{user_oid}
X-API-KEY: {ADMIN_KEY}
Content-Type: application/json

{
  "username": "{user_oid}",
  "desc": "Created by SSO portal for {user_name} ({user_email})",
  "labels": {
    "source": "oidc-portal-v0",
    "created_at": "{timestamp}"
  }
}
```

#### Update Consumer with Key-Auth Plugin
```http
PUT /apisix/admin/consumers/{user_oid}
X-API-KEY: {ADMIN_KEY}
Content-Type: application/json

{
  "username": "{user_oid}",
  "desc": "{existing_description}",
  "labels": {existing_labels},
  "plugins": {
    "key-auth": {
      "key": "{generated_api_key}"
    }
  }
}
```

## Error Handling

### Standard Error Format
All API errors follow this JSON format:
```json
{
    "error": "Error category/summary",
    "details": "Specific error message or technical details"
}
```

### Common Error Scenarios

#### Authentication Errors (401)
- Missing `X-User-Oid` header
- Empty or invalid `X-User-Oid` value

#### Server Errors (500)
- APISIX Admin API connectivity issues
- ETCD connection problems
- Consumer creation/update failures
- Unexpected credential state (multiple credentials found)

### Logging and Debugging

The Portal Backend implements comprehensive logging while maintaining security:

#### What Gets Logged
- User operations with user OID (not full identity)
- API key fingerprints: `key[:8]...key[-4:]`
- APISIX API responses and errors
- Consumer creation and updates
- Operational errors and warnings

#### What Never Gets Logged
- Full API keys
- OIDC client secrets
- Complete user identity information
- APISIX Admin API keys

#### Log Levels
- `INFO`: Normal operations, user actions, key operations
- `WARNING`: Authentication failures, validation issues
- `ERROR`: APISIX API failures, Consumer management errors
- `DEBUG`: Detailed request/response information (enabled via DEBUG=true)

## Development and Testing

### Direct API Testing
For development without OIDC flow:
```bash
# Test dashboard
curl -H "X-User-Oid: test-user-123" \
     -H "X-User-Name: Test User" \
     -H "X-User-Email: test@example.com" \
     http://localhost:3001/portal/

# Generate API key
curl -X POST \
     -H "X-User-Oid: test-user-123" \
     -H "Content-Type: application/json" \
     http://localhost:3001/portal/get-key

# Recycle API key
curl -X POST \
     -H "X-User-Oid: test-user-123" \
     -H "Content-Type: application/json" \
     http://localhost:3001/portal/recycle-key

# Health check
curl http://localhost:3001/health
```

### Integration Testing
Testing the complete OIDC → Portal flow:
```bash
# Start full stack
./scripts/lifecycle/start.sh --provider entraid

# Access portal (will redirect to OIDC)
open http://localhost:9080/portal/

# Check backend health
curl http://localhost:3001/health
```

## API Key Usage

Generated API keys can be used with APISIX Gateway endpoints:

```bash
# Example: Call protected API with generated key
curl -H "X-API-Key: wxyz5678-new-key-abcd1234" \
     http://localhost:9080/api/protected-endpoint
```

The keys are configured in APISIX Consumer `key-auth` plugin and work immediately after generation/recycling.

## Rate Limiting and Security

### Built-in Protections
- **1:1 User Mapping**: One user = one consumer = one key maximum
- **Immediate Invalidation**: Previous keys invalid immediately after recycle
- **CSPRNG Generation**: Cryptographically secure key generation
- **Header Validation**: Strict validation of required authentication headers

### Recommended Additional Security
- Configure rate limiting in APISIX for portal endpoints
- Monitor Consumer creation patterns for unusual activity
- Set up alerts for Consumer management API errors
- Regular key recycling policies for users

---

*This API documentation covers Portal Backend v0 implementation following the Portal Specifications.*