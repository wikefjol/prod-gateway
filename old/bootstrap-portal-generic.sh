#!/bin/sh
set -eu

# Generic Portal Route Loader for Self-Service API Key Portal
# This script sets up the OIDC-protected portal route using generic OIDC configuration

: "${ADMIN_KEY:?ADMIN_KEY not set}"
: "${OIDC_CLIENT_ID:?OIDC_CLIENT_ID not set}"
: "${OIDC_CLIENT_SECRET:?OIDC_CLIENT_SECRET not set}"
: "${OIDC_DISCOVERY_ENDPOINT:?OIDC_DISCOVERY_ENDPOINT not set}"
: "${OIDC_SESSION_SECRET:?OIDC_SESSION_SECRET not set}"
: "${OIDC_REDIRECT_URI:?OIDC_REDIRECT_URI not set}"
: "${PORTAL_BACKEND_HOST:?PORTAL_BACKEND_HOST not set}"

APISIX_ADMIN="http://apisix-dev:9180"  # service name inside docker network
OIDC_PROVIDER_NAME="${OIDC_PROVIDER_NAME:-generic}"

echo "🚀 Setting up Self-Service Portal with $OIDC_PROVIDER_NAME OIDC..."

# Wait for APISIX Admin API
echo "⏳ Waiting for APISIX Admin API..."
until curl -fsS "$APISIX_ADMIN/apisix/admin/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; do
  sleep 1
done
echo "✅ APISIX Admin API is ready"

# Wait for OIDC discovery to be ready (optional for some providers)
if [ "$OIDC_PROVIDER_NAME" = "keycloak" ]; then
    echo "⏳ Waiting for $OIDC_PROVIDER_NAME discovery to be ready..."
    max_attempts=60
    attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        if curl -fsS "$OIDC_DISCOVERY_ENDPOINT" >/dev/null 2>&1; then
            echo "✅ $OIDC_PROVIDER_NAME discovery is ready"
            break
        fi
        echo "   Attempt $attempt/$max_attempts - Discovery not ready yet..."
        sleep 5
        attempt=$((attempt+1))

        if [ "$attempt" -gt "$max_attempts" ]; then
            echo "❌ Discovery failed to become ready after $max_attempts attempts"
            echo "⚠️  Proceeding anyway - $OIDC_PROVIDER_NAME may still be starting..."
            break
        fi
    done
else
    echo "ℹ️  Skipping discovery check for $OIDC_PROVIDER_NAME (external provider)"
fi

echo "🔧 Applying Portal OIDC route from generic template..."

# Read JSON template and substitute environment variables
BODY=$(sed \
  "s|\$OIDC_CLIENT_ID|$OIDC_CLIENT_ID|g; \
   s|\$OIDC_CLIENT_SECRET|$OIDC_CLIENT_SECRET|g; \
   s|\$OIDC_DISCOVERY_ENDPOINT|$OIDC_DISCOVERY_ENDPOINT|g; \
   s|\$OIDC_SESSION_SECRET|$OIDC_SESSION_SECRET|g; \
   s|\$OIDC_REDIRECT_URI|$OIDC_REDIRECT_URI|g; \
   s|\$PORTAL_BACKEND_HOST|$PORTAL_BACKEND_HOST|g" \
   /opt/apisix-gateway/apisix/oidc-generic-route.json)

# Apply the portal route configuration
curl -fsS -X PUT \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  "$APISIX_ADMIN/apisix/admin/routes/portal-oidc-route"

echo "✅ Portal OIDC route configured successfully"

# Verify the route was created
echo "🔍 Verifying portal route configuration..."
ROUTE_INFO=$(curl -fsS -H "X-API-KEY: $ADMIN_KEY" "$APISIX_ADMIN/apisix/admin/routes/portal-oidc-route" | grep -o '"/portal/\*"' || echo "not found")

if [ "$ROUTE_INFO" = '"/portal/*"' ]; then
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
echo "   OIDC Provider: $OIDC_PROVIDER_NAME"
echo "   Client ID: $OIDC_CLIENT_ID"
echo "   Discovery: $OIDC_DISCOVERY_ENDPOINT"
echo "   Redirect URI: $OIDC_REDIRECT_URI"
echo "   Backend: $PORTAL_BACKEND_HOST"
echo ""
echo "🔗 Next Steps:"
echo "   1. Setup OIDC provider: ./scripts/setup-oidc-provider.sh"
echo "   2. Test OIDC flow: http://localhost:9080/portal"
echo ""
echo "✅ Ready for portal usage!"