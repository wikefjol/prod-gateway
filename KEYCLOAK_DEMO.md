# Keycloak OIDC Portal Demo Steps

This document demonstrates the working OIDC authentication flow for the Self-Service API Key Portal.

## Prerequisites

- Docker and docker-compose running
- Keycloak and APISIX services started via `docker-compose -f docker-compose.dev.yml up -d`

## Demo Steps

### 1. Verify Keycloak is Running

```bash
curl -s http://localhost:8080/realms/quickstart | jq '.realm'
```
**Expected output:** `"quickstart"`

### 2. Test OIDC Discovery Endpoint

```bash
curl -s http://localhost:8080/realms/quickstart/.well-known/openid-configuration | jq '{issuer, authorization_endpoint, token_endpoint}'
```
**Expected output:**
```json
{
  "issuer": "http://localhost:8080/realms/quickstart",
  "authorization_endpoint": "http://localhost:8080/realms/quickstart/protocol/openid-connect/auth",
  "token_endpoint": "http://localhost:8080/realms/quickstart/protocol/openid-connect/token"
}
```

### 3. Verify Portal Route Configuration

```bash
curl -s -H "X-API-KEY: b690a22de520f12fd9615ab43a443b5aa7239d7153ca2850" \
  "http://localhost:9180/apisix/admin/routes/portal-oidc-route" | \
  jq '.value.plugins."openid-connect".discovery'
```
**Expected output:** `"http://keycloak-dev:8080/realms/quickstart/.well-known/openid-configuration"`

### 4. Test OIDC Authentication Flow

```bash
curl -i "http://localhost:9080/portal/" --max-redirs 0
```

**Expected output:**
- `HTTP/1.1 302 Moved Temporarily` (not 500 or 404)
- `Set-Cookie: session=...` (session cookie being set)
- `Location: http://keycloak-dev:8080/realms/quickstart/protocol/openid-connect/auth?...` (redirect to Keycloak)

### 5. Verify Test Users Exist

You can access the Keycloak Admin UI to see the test users:

1. Go to: `http://localhost:8080/admin`
2. Login: `admin` / `admin`
3. Select realm: `quickstart` (top-left dropdown)
4. Navigate to: **Users**
5. You should see: `alice`, `bob`, `charlie`

### 6. Test Browser Flow (Optional)

Open a browser and go to: `http://localhost:9080/portal/`

You should:
1. Be redirected to Keycloak login page
2. Be able to login with: `alice` / `password123` (or `bob` / `password123`)
3. After login, be redirected back to `/portal/callback`
4. See a 500 error (expected - portal backend doesn't exist yet)

The important part is that **authentication happens** - the 500 error at the end is just because we haven't built the portal backend service yet.

## What This Demonstrates

✅ **OIDC Discovery Working**: Keycloak properly exposes discovery endpoints
✅ **APISIX Integration Working**: Portal route correctly configured with Keycloak
✅ **Authentication Flow Working**: Users are redirected to Keycloak for login
✅ **Session Management Working**: APISIX sets session cookies properly
✅ **Network Configuration Working**: Docker containers can communicate

## Expected vs Problem Scenarios

### ✅ SUCCESS (What you should see)
```bash
$ curl -i "http://localhost:9080/portal/" --max-redirs 0
HTTP/1.1 302 Moved Temporarily
Location: http://keycloak-dev:8080/realms/quickstart/protocol/openid-connect/auth?...
Set-Cookie: session=...
```

### ❌ FAILURE Examples (What would indicate problems)
```bash
# Discovery endpoint broken
HTTP/1.1 404 Not Found
{"error":"HTTP 404 Not Found"}

# OIDC plugin failing
HTTP/1.1 500 Internal Server Error

# Route not configured
HTTP/1.1 404 Not Found
{"error_msg":"404 Route Not Found"}
```

## Cleanup

When you're done testing:
```bash
docker-compose -f docker-compose.dev.yml down
```

---

**Status: READY FOR COMMIT** ✅
The OIDC authentication infrastructure is working correctly. The next step is to build the portal backend service that will handle authenticated users and manage API keys via the APISIX Admin API.