#!/usr/bin/env bash
set -euo pipefail

: "${ADMIN_KEY:?ADMIN_KEY not set}"
: "${AZURE_CLIENT_ID:?AZURE_CLIENT_ID not set}"
: "${AZURE_CLIENT_SECRET:?AZURE_CLIENT_SECRET not set}"
: "${AZURE_TENANT_ID:?AZURE_TENANT_ID not set}"
: "${OIDC_SESSION_SECRET:?OIDC_SESSION_SECRET not set}"
: "${REDIRECT_URI:?REDIRECT_URI not set}"
: "${BACKEND_HOST:?BACKEND_HOST not set}"

APISIX_ADMIN="http://apisix-dev:9180"  # service name inside docker network

# Wait for APISIX Admin API
echo "Waiting for APISIX Admin API..."
until curl -fsS "$APISIX_ADMIN/apisix/admin/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; do
  sleep 1
done

echo "Applying OIDC route from JSON template..."
# Read JSON template and substitute environment variables
BODY=$(sed "s/\$AZURE_CLIENT_ID/$AZURE_CLIENT_ID/g; s/\$AZURE_CLIENT_SECRET/$AZURE_CLIENT_SECRET/g; s/\$AZURE_TENANT_ID/$AZURE_TENANT_ID/g; s/\$OIDC_SESSION_SECRET/$OIDC_SESSION_SECRET/g; s|\$REDIRECT_URI|$REDIRECT_URI|g; s/\$BACKEND_HOST/$BACKEND_HOST/g" /opt/apisix-gateway/apisix/oidc-route.json)

curl -fsS -X PUT \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  "$APISIX_ADMIN/apisix/admin/routes/oidc-auth-callback"

echo "OIDC route upserted successfully."