#!/bin/sh
# Universal OIDC Bootstrap Script
# Configures APISIX routes based on provider configuration

set -eu

# Logging functions
log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_warning() {
    echo "⚠️  $*"
}

log_error() {
    echo "❌ $*" >&2
}

# Validation - ensure required variables are set
validate_environment() {
    local required_vars="ADMIN_KEY OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_DISCOVERY_ENDPOINT OIDC_REDIRECT_URI OIDC_SESSION_SECRET OIDC_PROVIDER_NAME"

    for var in $required_vars; do
        eval "value=\${$var:-}"
        if [ -z "$value" ]; then
            log_error "Required environment variable not set: $var"
            return 1
        fi
    done

    log_info "Environment validation passed"
}

# Detect network context (container vs host)
detect_network_context() {
    # Method 0: Explicit override (single source of truth)
    if [ -n "${APISIX_NETWORK_CONTEXT:-}" ]; then
        echo "${APISIX_NETWORK_CONTEXT}"
        return 0
    fi

    # Method 1: Check if running in Docker container
    if [ -f /.dockerenv ]; then
        echo "container"
        return 0
    fi

    # Method 2: Check for Docker-specific environment
    if [ -n "${DOCKER_CONTAINER:-}" ]; then
        echo "container"
        return 0
    fi

    # Method 3: Test connectivity to container network
    if command -v nc >/dev/null 2>&1 && nc -z "apisix-dev" "${APISIX_ADMIN_PORT:-9180}" 2>/dev/null; then
        echo "container"
        return 0
    fi

    # Default to host context
    echo "host"
    return 0
}

# Wait for APISIX to be ready
wait_for_apisix() {
    # Intelligent context detection for single source of truth
    local network_context
    network_context=$(detect_network_context)

    local apisix_admin
    if [ "$network_context" = "container" ]; then
        apisix_admin="${APISIX_ADMIN_API_CONTAINER}"
        log_info "Detected container context"
    else
        apisix_admin="${APISIX_ADMIN_API}"
        log_info "Detected host context"
    fi

    local max_attempts=60
    local attempt=1

    log_info "Waiting for APISIX Admin API at $apisix_admin..."

    while [ $attempt -le $max_attempts ]; do
        if curl -fsS "$apisix_admin/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; then
            log_success "APISIX Admin API is ready"
            return 0
        fi

        if [ $attempt -eq $max_attempts ]; then
            log_error "APISIX Admin API failed to become ready after $max_attempts attempts"
            return 1
        fi

        printf "."
        sleep 1
        attempt=$((attempt + 1))
    done
}

# Wait for provider-specific services (if applicable)
wait_for_provider() {
    case "$OIDC_PROVIDER_NAME" in
        "keycloak")
            wait_for_keycloak
            ;;
        "entraid")
            # EntraID is external - validate discovery endpoint accessibility
            validate_entraid_discovery
            ;;
        *)
            log_warning "Unknown provider: $OIDC_PROVIDER_NAME, skipping provider-specific checks"
            ;;
    esac
}

wait_for_keycloak() {
    # Single source of truth: use config-driven Keycloak URL
    local keycloak_url="${KEYCLOAK_ADMIN_URL}"
    local max_attempts=60
    local attempt=1

    log_info "Waiting for Keycloak at $keycloak_url..."

    while [ $attempt -le $max_attempts ]; do
        if curl -fsS "$keycloak_url/health/ready" >/dev/null 2>&1; then
            log_success "Keycloak is ready"
            return 0
        fi

        if [ $attempt -eq $max_attempts ]; then
            log_warning "Keycloak failed to become ready after $max_attempts attempts"
            log_warning "Proceeding with configuration - Keycloak may still be starting"
            return 0
        fi

        printf "."
        sleep 2
        attempt=$((attempt + 1))
    done
}

validate_entraid_discovery() {
    if echo "$OIDC_DISCOVERY_ENDPOINT" | grep -q "placeholder"; then
        log_warning "EntraID discovery endpoint contains placeholder values"
        log_warning "Please update secrets/entraid-dev.env with actual credentials"
        return 0
    fi

    log_info "Validating EntraID discovery endpoint..."

    if curl -fsS "$OIDC_DISCOVERY_ENDPOINT" >/dev/null 2>&1; then
        log_success "EntraID discovery endpoint is accessible"
    else
        log_warning "EntraID discovery endpoint is not accessible"
        log_warning "This may be normal if using placeholder values or due to network restrictions"
    fi
}

# Configure OIDC routes
configure_oidc_routes() {
    # Intelligent context detection for single source of truth
    local network_context
    network_context=$(detect_network_context)

    local apisix_admin
    if [ "$network_context" = "container" ]; then
        apisix_admin="${APISIX_ADMIN_API_CONTAINER}"
    else
        apisix_admin="${APISIX_ADMIN_API}"
    fi

    log_info "Configuring OIDC routes for provider: $OIDC_PROVIDER_NAME"
    log_info "Using APISIX Admin API ($network_context context): $apisix_admin"

    # Use existing portal route template (more advanced)
    configure_portal_route "$apisix_admin"

    # Also configure legacy callback route for backward compatibility
    configure_callback_route "$apisix_admin"
}

configure_portal_route() {
    local apisix_admin="$1"
    local template_file="/opt/apisix-gateway/apisix/oidc-generic-route.json"

    if [ ! -f "$template_file" ]; then
        log_error "Portal route template not found: $template_file"
        return 1
    fi

    log_info "Applying portal OIDC route..."

    # Substitute environment variables in template
    local body
    body=$(sed "s|\$OIDC_CLIENT_ID|$OIDC_CLIENT_ID|g; \
                s|\$OIDC_CLIENT_SECRET|$OIDC_CLIENT_SECRET|g; \
                s|\$OIDC_DISCOVERY_ENDPOINT|$OIDC_DISCOVERY_ENDPOINT|g; \
                s|\$OIDC_SESSION_SECRET|$OIDC_SESSION_SECRET|g; \
                s|\$OIDC_REDIRECT_URI|$OIDC_REDIRECT_URI|g; \
                s|\$PORTAL_BACKEND_HOST|${PORTAL_BACKEND_HOST:-portal-backend:3000}|g" \
                "$template_file")

    # Apply the route configuration
    if curl -fsS -X PUT \
        -H "X-API-KEY: $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$apisix_admin/routes/portal-oidc-route" >/dev/null; then
        log_success "Portal OIDC route configured successfully"
    else
        log_error "Failed to configure portal OIDC route"
        return 1
    fi
}

configure_callback_route() {
    local apisix_admin="$1"
    local template_file="/opt/apisix-gateway/apisix/oidc-route.json"

    # Check if legacy template exists
    if [ ! -f "$template_file" ]; then
        log_info "Legacy callback route template not found, skipping"
        return 0
    fi

    log_info "Applying legacy callback OIDC route..."

    # For backward compatibility, support both new and old variable names
    local azure_client_id="${AZURE_CLIENT_ID:-$OIDC_CLIENT_ID}"
    local azure_client_secret="${AZURE_CLIENT_SECRET:-$OIDC_CLIENT_SECRET}"
    local azure_tenant_id="${AZURE_TENANT_ID:-}"
    local redirect_uri="${REDIRECT_URI:-$OIDC_REDIRECT_URI}"
    local backend_host="${BACKEND_HOST:-app-backend-dev:3000}"

    # For EntraID, extract tenant ID from discovery URL if not set
    if [ "$OIDC_PROVIDER_NAME" = "entraid" ] && [ -z "$azure_tenant_id" ]; then
        azure_tenant_id=$(echo "$OIDC_DISCOVERY_ENDPOINT" | sed -n 's|.*microsoftonline.com/\([^/]*\)/.*|\1|p')
    fi

    # Substitute environment variables in template
    local body
    body=$(sed "s|\$AZURE_CLIENT_ID|$azure_client_id|g; \
                s|\$AZURE_CLIENT_SECRET|$azure_client_secret|g; \
                s|\$AZURE_TENANT_ID|$azure_tenant_id|g; \
                s|\$OIDC_SESSION_SECRET|$OIDC_SESSION_SECRET|g; \
                s|\$REDIRECT_URI|$redirect_uri|g; \
                s|\$BACKEND_HOST|$backend_host|g" \
                "$template_file")

    # Apply the route configuration
    if curl -fsS -X PUT \
        -H "X-API-KEY: $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$apisix_admin/routes/oidc-auth-callback" >/dev/null; then
        log_success "Legacy callback OIDC route configured successfully"
    else
        log_error "Failed to configure legacy callback OIDC route"
        return 1
    fi
}

# Verify route configuration
verify_routes() {
    # Intelligent context detection for single source of truth
    local network_context
    network_context=$(detect_network_context)

    local apisix_admin
    if [ "$network_context" = "container" ]; then
        apisix_admin="${APISIX_ADMIN_API_CONTAINER}"
    else
        apisix_admin="${APISIX_ADMIN_API}"
    fi

    log_info "Verifying route configuration at $apisix_admin ($network_context context)..."

    # Get all routes
    local routes_response
    if routes_response=$(curl -fsS -H "X-API-KEY: $ADMIN_KEY" "$apisix_admin/routes" 2>/dev/null); then
        # Count configured routes
        local route_count
        route_count=$(echo "$routes_response" | grep -o '"total":[0-9]*' | cut -d':' -f2 || echo "0")

        log_success "Routes configured successfully"
        log_info "Total routes: $route_count"

        # List route IDs if possible (limited shell JSON parsing)
        echo "$routes_response" | grep -o '"id":"[^"]*"' | sed 's/"id"://;s/"//g' | while read -r route_id; do
            log_info "  - Route: $route_id"
        done
    else
        log_error "Failed to verify route configuration"
        return 1
    fi
}

# Main bootstrap function
main() {
    echo "🚀 APISIX OIDC Bootstrap"
    echo "======================="
    echo "Provider: $OIDC_PROVIDER_NAME"
    echo "Discovery: $OIDC_DISCOVERY_ENDPOINT"
    echo "Client ID: $OIDC_CLIENT_ID"
    echo "Redirect URI: $OIDC_REDIRECT_URI"
    echo ""

    # Bootstrap sequence
    validate_environment
    wait_for_apisix
    wait_for_provider
    configure_oidc_routes
    verify_routes

    echo ""
    log_success "🎉 OIDC bootstrap completed successfully!"
    echo ""
    echo "Next steps:"
    DATA_PLANE=${DATA_PLANE:-http://localhost:9080}
    echo "  1. Test portal access: $DATA_PLANE/portal"
    echo "  2. Check route config: curl -H 'X-API-KEY: $ADMIN_KEY' ${APISIX_ADMIN_API}/routes"
    echo "  3. Review logs: docker logs apisix-dev"
    echo ""
}

# Execute main function
main "$@"