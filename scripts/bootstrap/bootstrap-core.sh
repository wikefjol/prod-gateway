#!/bin/bash
# APISIX Core Routes Bootstrap Script
# Deploys essential routes (health, portal, OIDC) without requiring API provider keys

set -euo pipefail

# Colors and logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}INFO:${NC} $*" >&2; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }
log_error() { echo -e "${RED}ERROR:${NC} $*" >&2; }

# Configuration
APISIX_DIR="$(dirname "$0")/../../apisix"
ENVIRONMENT="${1:-dev}"

# Core route files (do not require API provider keys)
CORE_ROUTES=(
    "health-simple.json"
    "portal-redirect-route.json"
    "oidc-generic-route.json"
    "root-redirect-route.json"
)

# Optional provider routes (require API keys)
PROVIDER_ROUTES=(
    "anthropic-route.json"
    "openai-route.json"
    "litellm-route.json"
)

# Load environment configuration
load_environment() {
    log_info "Loading $ENVIRONMENT environment configuration..."

    # Load environment configuration
    if [[ -f "scripts/core/environment.sh" ]]; then
        source scripts/core/environment.sh
        setup_environment "entraid" "$ENVIRONMENT"
    else
        log_error "Environment setup script not found"
        return 1
    fi

    # Validate required variables for core routes
    local required_vars=(
        "ADMIN_KEY"
        "APISIX_ADMIN_API_CONTAINER"
        "OIDC_CLIENT_ID"
        "OIDC_CLIENT_SECRET"
        "OIDC_DISCOVERY_ENDPOINT"
        "OIDC_REDIRECT_URI"
        "OIDC_SESSION_SECRET"
        "PORTAL_BACKEND_HOST"
    )

    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Core routes require OIDC and admin configuration"
        return 1
    fi

    # Override admin API endpoint for external script execution
    if [[ "$ENVIRONMENT" == "dev" ]]; then
        APISIX_ADMIN_API="http://localhost:9180/apisix/admin"
    elif [[ "$ENVIRONMENT" == "test" ]]; then
        APISIX_ADMIN_API="http://localhost:9181/apisix/admin"
    else
        APISIX_ADMIN_API="$APISIX_ADMIN_API_CONTAINER"
    fi

    log_success "Environment loaded for $ENVIRONMENT"
    log_info "Admin API: $APISIX_ADMIN_API"
    log_info "OIDC Client: $OIDC_CLIENT_ID"
    log_info "Portal Backend: $PORTAL_BACKEND_HOST"
}

# Deploy a single route
deploy_route() {
    local route_file="$1"
    local route_path="$APISIX_DIR/$route_file"

    if [[ ! -f "$route_path" ]]; then
        log_error "Route file not found: $route_path"
        return 1
    fi

    # Extract route ID from the JSON file
    local route_id
    route_id=$(jq -r '.id' "$route_path" 2>/dev/null)
    if [[ "$route_id" == "null" || -z "$route_id" ]]; then
        log_error "Cannot extract route ID from $route_file"
        return 1
    fi

    log_info "Deploying route: $route_id"

    # Deploy the route with environment variable substitution
    local response
    local route_json
    route_json=$(envsubst < "$route_path")
    response=$(curl -s -w "\n%{http_code}" \
        -X PUT \
        -H "X-API-KEY: $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        "$APISIX_ADMIN_API/routes/$route_id" \
        -d "$route_json" 2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
        log_success "✅ Route deployed: $route_id"
    else
        log_error "❌ Failed to deploy $route_id (HTTP $http_code)"
        if [[ -n "$body" ]]; then
            echo "$body" | jq . 2>/dev/null || echo "$body"
        fi
        return 1
    fi
}

# Deploy all core routes
deploy_core_routes() {
    log_info "=== DEPLOYING CORE ROUTES ==="

    local deployed=0
    local failed=0

    for route_file in "${CORE_ROUTES[@]}"; do
        if deploy_route "$route_file"; then
            ((deployed++))
        else
            ((failed++))
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_success "All $deployed core routes deployed successfully"
        return 0
    else
        log_error "$failed routes failed to deploy"
        return 1
    fi
}

# Optionally deploy provider routes (if API keys are available)
deploy_provider_routes() {
    log_info "=== DEPLOYING PROVIDER ROUTES (OPTIONAL) ==="

    # Check if provider API keys are available
    local provider_keys_available=true
    local missing_provider_vars=()

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        missing_provider_vars+=("OPENAI_API_KEY")
        provider_keys_available=false
    fi

    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        missing_provider_vars+=("ANTHROPIC_API_KEY")
        provider_keys_available=false
    fi

    if [[ -z "${LITELLM_KEY:-}" ]]; then
        missing_provider_vars+=("LITELLM_KEY")
        provider_keys_available=false
    fi

    if [[ "$provider_keys_available" == "false" ]]; then
        log_warning "Provider API keys not available: ${missing_provider_vars[*]}"
        log_warning "Skipping provider routes - only core routes will be deployed"
        return 0
    fi

    local deployed=0
    local failed=0

    for route_file in "${PROVIDER_ROUTES[@]}"; do
        if deploy_route "$route_file"; then
            ((deployed++))
        else
            ((failed++))
            # Don't fail completely for optional provider routes
        fi
    done

    if [[ $deployed -gt 0 ]]; then
        log_success "$deployed provider routes deployed"
    fi
    if [[ $failed -gt 0 ]]; then
        log_warning "$failed provider routes failed (check API keys)"
    fi
}

# Verify routes are working
verify_routes() {
    log_info "=== VERIFYING ROUTES ==="

    local port
    if [[ "$ENVIRONMENT" == "test" ]]; then
        port="9081"
    else
        port="9080"
    fi

    # Test health route
    if curl -s "http://localhost:$port/health" | grep -q "ok"; then
        log_success "Health route working on port $port"
    else
        log_warning "Health route may not be working on port $port"
    fi

    # Test portal redirect
    local portal_response
    portal_response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/portal" || echo "failed")
    if [[ "$portal_response" == "302" ]]; then
        log_success "Portal redirect working on port $port"
    else
        log_warning "Portal redirect response: $portal_response"
    fi

    # List all configured routes
    log_info "Current routes in APISIX:"
    curl -s -H "X-API-KEY: $ADMIN_KEY" "$APISIX_ADMIN_API/routes" | \
        jq -r '.list[]?.value.id // "unknown"' 2>/dev/null | \
        while read -r route_id; do
            log_info "  - $route_id"
        done
}

# Main execution
main() {
    log_info "🚀 APISIX Core Routes Bootstrap"
    log_info "Environment: $ENVIRONMENT"
    echo ""

    # Load environment
    if ! load_environment; then
        exit 1
    fi

    echo ""

    # Deploy core routes (always required)
    if ! deploy_core_routes; then
        log_error "Failed to deploy core routes"
        exit 1
    fi

    echo ""

    # Deploy provider routes (optional, based on available keys)
    deploy_provider_routes

    echo ""

    # Verify deployment
    verify_routes

    echo ""
    log_success "🎉 APISIX bootstrap completed for $ENVIRONMENT environment"

    if [[ "$ENVIRONMENT" == "test" ]]; then
        log_info "Test environment accessible on: http://localhost:9081"
        log_info "Admin API: http://localhost:9181"
    else
        log_info "Dev environment accessible on: http://localhost:9080"
        log_info "Admin API: http://localhost:9180"
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [environment]"
    echo ""
    echo "Arguments:"
    echo "  environment    Target environment (dev|test) [default: dev]"
    echo ""
    echo "Examples:"
    echo "  $0           # Bootstrap dev environment"
    echo "  $0 dev       # Bootstrap dev environment"
    echo "  $0 test      # Bootstrap test environment"
    echo ""
    echo "This script deploys core APISIX routes without requiring API provider keys."
    echo "Provider routes (OpenAI, Anthropic, LiteLLM) are deployed only if keys are available."
}

# Handle arguments
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_usage
    exit 0
elif [[ "${1:-}" != "" && "${1:-}" != "dev" && "${1:-}" != "test" ]]; then
    log_error "Invalid environment: $1"
    show_usage
    exit 1
fi

main