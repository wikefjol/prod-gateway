#!/usr/bin/env bash
set -euo pipefail

: "${ADMIN_KEY:?ADMIN_KEY not set}"
: "${AZURE_CLIENT_ID:?AZURE_CLIENT_ID not set}"
: "${AZURE_CLIENT_SECRET:?AZURE_CLIENT_SECRET not set}"
: "${AZURE_TENANT_ID:?AZURE_TENANT_ID not set}"
: "${OIDC_SESSION_SECRET:?OIDC_SESSION_SECRET not set}"

APISIX_ADMIN="http://apisix-dev:9180"  # service name inside docker network

# Wait for APISIX Admin API
echo "Waiting for APISIX Admin API..."
until curl -fsS "$APISIX_ADMIN/apisix/admin/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; do
  sleep 1
done

echo "Applying OIDC route..."
# Create JSON body with env vars (no envsubst dependency)
BODY=$(cat <<EOF
{
  "id": "oidc-auth-callback",
  "uri": "/v1/auth/oidc/callback",
  "methods": ["GET", "POST"],
  "plugins": {
    "openid-connect": {
      "client_id": "$AZURE_CLIENT_ID",
      "client_secret": "$AZURE_CLIENT_SECRET",
      "discovery": "https://login.microsoftonline.com/$AZURE_TENANT_ID/v2.0/.well-known/openid-configuration",
      "scope": "openid profile email",
      "redirect_uri": "http://localhost:9080/v1/auth/oidc/callback",
      "bearer_only": false,
      "ssl_verify": false,
      "timeout": 3,
      "session": {
        "secret": "$OIDC_SESSION_SECRET"
      }
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "app-backend-dev:3000": 1
    }
  }
}
EOF
)

curl -fsS -X PUT \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  "$APISIX_ADMIN/apisix/admin/routes/oidc-auth-callback"

echo "OIDC route upserted successfully."