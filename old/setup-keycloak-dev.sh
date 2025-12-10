#!/bin/bash

# Setup Keycloak realm, client, and test users for APISIX portal development
# This script configures Keycloak for the Self-Service API Key Portal

set -e

KEYCLOAK_URL="http://localhost:8080"
REALM_NAME="quickstart"
CLIENT_ID="apisix-portal"
ADMIN_USER="admin"
ADMIN_PASS="admin"

echo "🔧 Setting up Keycloak for APISIX Portal Development..."

# Function to wait for Keycloak to be ready
wait_for_keycloak() {
    echo "⏳ Waiting for Keycloak to be ready..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        # Test by trying to get a token from the master realm
        if curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=$ADMIN_USER" \
            -d "password=$ADMIN_PASS" \
            -d "grant_type=password" \
            -d "client_id=admin-cli" > /dev/null 2>&1; then
            echo "✅ Keycloak is ready!"
            return 0
        fi
        echo "   Attempt $attempt/$max_attempts - Keycloak not ready yet..."
        sleep 5
        ((attempt++))
    done

    echo "❌ Keycloak failed to become ready after $max_attempts attempts"
    exit 1
}

# Function to get admin access token
get_admin_token() {
    local token=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=$ADMIN_USER" \
        -d "password=$ADMIN_PASS" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" | \
        jq -r '.access_token // empty')

    if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo "❌ Failed to get admin access token"
        exit 1
    fi

    echo "$token"
}

# Function to create realm
create_realm() {
    local token=$1
    echo "🏗️  Creating realm '$REALM_NAME'..."

    local realm_config=$(cat <<EOF
{
    "realm": "$REALM_NAME",
    "enabled": true,
    "displayName": "APISIX Portal Development",
    "accessTokenLifespan": 300,
    "accessTokenLifespanForImplicitFlow": 900,
    "ssoSessionIdleTimeout": 1800,
    "ssoSessionMaxLifespan": 36000,
    "offlineSessionIdleTimeout": 2592000,
    "accessCodeLifespan": 60,
    "accessCodeLifespanUserAction": 300,
    "registrationAllowed": false,
    "registrationEmailAsUsername": false,
    "rememberMe": false,
    "verifyEmail": false,
    "loginWithEmailAllowed": true,
    "duplicateEmailsAllowed": false,
    "resetPasswordAllowed": false,
    "editUsernameAllowed": false
}
EOF
)

    local response=$(curl -s -w "%{http_code}" -X POST "$KEYCLOAK_URL/admin/realms" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$realm_config")

    local http_code="${response: -3}"
    if [ "$http_code" = "201" ] || [ "$http_code" = "409" ]; then
        echo "✅ Realm '$REALM_NAME' ready"
    else
        echo "❌ Failed to create realm. HTTP code: $http_code"
        echo "Response: ${response%???}"
        exit 1
    fi
}

# Function to create OIDC client
create_client() {
    local token=$1
    echo "🔐 Creating OIDC client '$CLIENT_ID'..."

    local client_config=$(cat <<EOF
{
    "clientId": "$CLIENT_ID",
    "name": "APISIX Portal Client",
    "description": "OpenID Connect client for APISIX Self-Service Portal",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "your-client-secret-from-keycloak",
    "redirectUris": [
        "http://localhost:9080/portal/callback",
        "http://localhost:9080/portal/*"
    ],
    "webOrigins": [
        "http://localhost:9080"
    ],
    "protocol": "openid-connect",
    "attributes": {
        "saml.assertion.signature": "false",
        "saml.force.post.binding": "false",
        "saml.multivalued.roles": "false",
        "saml.encrypt": "false",
        "oauth2.device.authorization.grant.enabled": "false",
        "backchannel.logout.revoke.offline.tokens": "false",
        "saml.server.signature": "false",
        "saml.server.signature.keyinfo.ext": "false",
        "exclude.session.state.from.auth.response": "false",
        "oidc.ciba.grant.enabled": "false",
        "saml.artifact.binding": "false",
        "backchannel.logout.session.required": "true",
        "client_credentials.use_refresh_token": "false",
        "saml_force_name_id_format": "false",
        "saml.client.signature": "false",
        "tls.client.certificate.bound.access.tokens": "false",
        "require.pushed.authorization.requests": "false",
        "saml.authnstatement": "false",
        "display.on.consent.screen": "false",
        "saml.onetimeuse.condition": "false"
    },
    "authenticationFlowBindingOverrides": {},
    "fullScopeAllowed": true,
    "nodeReRegistrationTimeout": -1,
    "protocolMappers": [
        {
            "name": "username",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-usermodel-property-mapper",
            "consentRequired": false,
            "config": {
                "userinfo.token.claim": "true",
                "user.attribute": "username",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "preferred_username",
                "jsonType.label": "String"
            }
        },
        {
            "name": "email",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-usermodel-property-mapper",
            "consentRequired": false,
            "config": {
                "userinfo.token.claim": "true",
                "user.attribute": "email",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "email",
                "jsonType.label": "String"
            }
        }
    ],
    "defaultClientScopes": [
        "web-origins",
        "profile",
        "roles",
        "email"
    ],
    "optionalClientScopes": [
        "address",
        "phone",
        "offline_access",
        "microprofile-jwt"
    ]
}
EOF
)

    local response=$(curl -s -w "%{http_code}" -X POST "$KEYCLOAK_URL/admin/realms/$REALM_NAME/clients" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$client_config")

    local http_code="${response: -3}"
    if [ "$http_code" = "201" ]; then
        echo "✅ OIDC client '$CLIENT_ID' created successfully"
    elif [ "$http_code" = "409" ]; then
        echo "✅ OIDC client '$CLIENT_ID' already exists"
    else
        echo "❌ Failed to create OIDC client. HTTP code: $http_code"
        echo "Response: ${response%???}"
        exit 1
    fi
}

# Function to create test users
create_test_users() {
    local token=$1
    echo "👥 Creating test users..."

    local users=("alice" "bob" "charlie")

    for username in "${users[@]}"; do
        local user_config=$(cat <<EOF
{
    "username": "$username",
    "enabled": true,
    "totp": false,
    "emailVerified": true,
    "firstName": "$(echo $username | sed 's/./\U&/')",
    "lastName": "Test",
    "email": "$username@example.com",
    "credentials": [
        {
            "type": "password",
            "value": "password123",
            "temporary": false
        }
    ],
    "attributes": {
        "locale": ["en"]
    }
}
EOF
)

        local response=$(curl -s -w "%{http_code}" -X POST "$KEYCLOAK_URL/admin/realms/$REALM_NAME/users" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$user_config")

        local http_code="${response: -3}"
        if [ "$http_code" = "201" ]; then
            echo "✅ Test user '$username' created successfully"
        elif [ "$http_code" = "409" ]; then
            echo "✅ Test user '$username' already exists"
        else
            echo "⚠️  Failed to create test user '$username'. HTTP code: $http_code"
        fi
    done
}

# Main execution
echo "🚀 Starting Keycloak configuration..."

wait_for_keycloak

echo "🔑 Getting admin access token..."
ADMIN_TOKEN=$(get_admin_token)

create_realm "$ADMIN_TOKEN"
create_client "$ADMIN_TOKEN"
create_test_users "$ADMIN_TOKEN"

echo ""
echo "🎉 Keycloak setup completed successfully!"
echo ""
echo "📋 Configuration Summary:"
echo "   Keycloak URL: $KEYCLOAK_URL"
echo "   Realm: $REALM_NAME"
echo "   Client ID: $CLIENT_ID"
echo "   Client Secret: your-client-secret-from-keycloak"
echo ""
echo "👤 Test Users (password: password123):"
echo "   - alice@example.com"
echo "   - bob@example.com"
echo "   - charlie@example.com"
echo ""
echo "🔗 Access URLs:"
echo "   Admin Console: $KEYCLOAK_URL/admin"
echo "   Account Console: $KEYCLOAK_URL/realms/$REALM_NAME/account"
echo "   OIDC Discovery: $KEYCLOAK_URL/realms/$REALM_NAME/.well-known/openid-connect/configuration"
echo ""
echo "✅ Ready for APISIX Portal integration!"