#!/bin/bash

# Generic OIDC Provider Setup Script
# This script sets up the appropriate OIDC provider based on OIDC_PROVIDER_NAME

set -e

: "${OIDC_PROVIDER_NAME:?OIDC_PROVIDER_NAME not set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Setting up OIDC provider: $OIDC_PROVIDER_NAME"

case "$OIDC_PROVIDER_NAME" in
  "keycloak")
    echo "🏗️ Setting up Keycloak OIDC provider..."
    "$SCRIPT_DIR/setup-keycloak-dev.sh"
    ;;
  "entra-id")
    echo "🏗️ Setting up Entra ID OIDC provider..."
    if [ -f "$SCRIPT_DIR/setup-entra-id-dev.sh" ]; then
      "$SCRIPT_DIR/setup-entra-id-dev.sh"
    else
      echo "⚠️  Entra ID setup script not found. Manual configuration required."
      echo "📋 Required Entra ID Configuration:"
      echo "   1. Register application in Azure AD"
      echo "   2. Configure redirect URI: $OIDC_REDIRECT_URI"
      echo "   3. Enable ID tokens"
      echo "   4. Update OIDC_CLIENT_ID and OIDC_CLIENT_SECRET in .dev.env"
      echo ""
      echo "✅ OIDC route will use generic configuration from environment variables"
    fi
    ;;
  *)
    echo "❌ Unknown OIDC provider: $OIDC_PROVIDER_NAME"
    echo "📋 Supported providers: keycloak, entra-id"
    exit 1
    ;;
esac

echo ""
echo "✅ OIDC provider setup completed successfully!"
echo "🔗 Provider: $OIDC_PROVIDER_NAME"
echo "🔗 Client ID: $OIDC_CLIENT_ID"
echo "🔗 Discovery: $OIDC_DISCOVERY_ENDPOINT"
echo "🔗 Redirect URI: $OIDC_REDIRECT_URI"