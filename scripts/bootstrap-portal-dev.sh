#!/usr/bin/env bash
set -euo pipefail

# Portal Route Loader for Self-Service API Key Portal
# This script sets up the OIDC-protected portal route using Keycloak

: "${ADMIN_KEY:?ADMIN_KEY not set}"
: "${KEYCLOAK_CLIENT_ID:?KEYCLOAK_CLIENT_ID not set}"
: "${KEYCLOAK_CLIENT_SECRET:?KEYCLOAK_CLIENT_SECRET not set}"
: "${KEYCLOAK_DISCOVERY:?KEYCLOAK_DISCOVERY not set}"
: "${OIDC_SESSION_SECRET:?OIDC_SESSION_SECRET not set}"
: "${PORTAL_REDIRECT_URI:?PORTAL_REDIRECT_URI not set}"
: "${PORTAL_BACKEND_HOST:?PORTAL_BACKEND_HOST not set}"

APISIX_ADMIN="http://apisix-dev:9180"  # service name inside docker network
KEYCLOAK_URL="http://keycloak-dev:8080"  # service name inside docker network

echo "🚀 Setting up Self-Service Portal with Keycloak OIDC..."

# Wait for APISIX Admin API
echo "⏳ Waiting for APISIX Admin API..."
until curl -fsS "$APISIX_ADMIN/apisix/admin/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; do
  sleep 1
done
echo "✅ APISIX Admin API is ready"

# Wait for Keycloak to be ready
echo "⏳ Waiting for Keycloak to be ready..."
max_attempts=60
attempt=1

while [ $attempt -le $max_attempts ]; do
    if curl -fsS "$KEYCLOAK_URL/health/ready" >/dev/null 2>&1; then
        echo "✅ Keycloak is ready"
        break
    fi
    echo "   Attempt $attempt/$max_attempts - Keycloak not ready yet..."
    sleep 5
    ((attempt++))

    if [ $attempt -gt $max_attempts ]; then
        echo "❌ Keycloak failed to become ready after $max_attempts attempts"
        echo "⚠️  Proceeding anyway - Keycloak may still be starting..."
        break
    fi
done

echo "🔧 Applying Portal OIDC route from JSON template..."

# Read JSON template and substitute environment variables
BODY=$(sed \
  "s/\$KEYCLOAK_CLIENT_ID/$KEYCLOAK_CLIENT_ID/g; \
   s/\$KEYCLOAK_CLIENT_SECRET/$KEYCLOAK_CLIENT_SECRET/g; \
   s|\$KEYCLOAK_DISCOVERY|$KEYCLOAK_DISCOVERY|g; \
   s/\$OIDC_SESSION_SECRET/$OIDC_SESSION_SECRET/g; \
   s|\$PORTAL_REDIRECT_URI|$PORTAL_REDIRECT_URI|g; \
   s/\$PORTAL_BACKEND_HOST/$PORTAL_BACKEND_HOST/g" \
   /opt/apisix-gateway/apisix/portal-route.json)

# Apply the portal route configuration
curl -fsS -X PUT \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  "$APISIX_ADMIN/apisix/admin/routes/portal-oidc-route"

echo "✅ Portal OIDC route configured successfully"

# Verify the route was created
echo "🔍 Verifying portal route configuration..."
ROUTE_INFO=$(curl -fsS -H "X-API-KEY: $ADMIN_KEY" "$APISIX_ADMIN/apisix/admin/routes/portal-oidc-route" | jq -r '.value.uri // "not found"')

if [ "$ROUTE_INFO" = "/portal/*" ]; then
    echo "✅ Portal route verification successful: $ROUTE_INFO"
else
    echo "❌ Portal route verification failed. Found: $ROUTE_INFO"
    exit 1
fi

echo ""
echo "🎉 Portal setup completed successfully!"
echo ""
echo "📋 Portal Configuration Summary:"
echo "   Portal URL: http://localhost:9080/portal"
echo "   Route ID: portal-oidc-route"
echo "   OIDC Provider: Keycloak (quickstart realm)"
echo "   Redirect URI: $PORTAL_REDIRECT_URI"
echo "   Backend: $PORTAL_BACKEND_HOST"
echo ""
echo "🔗 Next Steps:"
echo "   1. Setup Keycloak realm and client: ./scripts/setup-keycloak-dev.sh"
echo "   2. Develop portal backend service"
echo "   3. Test OIDC flow: http://localhost:9080/portal"
echo ""
echo "✅ Ready for portal backend development!"