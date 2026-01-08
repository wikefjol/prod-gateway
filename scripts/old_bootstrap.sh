#!/bin/bash
# APISIX Routes Bootstrap - Simplified
# Loads essential routes into APISIX
# Usage: ./scripts/bootstrap.sh [dev|test]

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROUTES_DIR="$PROJECT_ROOT/apisix/routes"

# Environment-specific admin API endpoints
if [ "$ENVIRONMENT" = "test" ]; then
    ADMIN_API="http://127.0.0.1:9181/apisix/admin"
else
    ADMIN_API="http://127.0.0.1:9180/apisix/admin"
fi

# Helper functions
log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_error() {
    echo "❌ $*" >&2
}

# Load environment variables from secrets
ENV_FILE="$PROJECT_ROOT/.env.$ENVIRONMENT"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  log_error "Missing env file: $ENV_FILE"
  exit 1
fi

: "${ADMIN_KEY:?ADMIN_KEY missing in $ENV_FILE}"

# Core routes (always deployed)
CORE_ROUTES=(
    "health-route.json"
    "portal-redirect-route.json"
    "oidc-generic-route.json"
    "root-redirect-route.json"
)

# Provider routes (optional, require API keys)
PROVIDER_ROUTES=(
    "anthropic-route.json"
    "openai-route.json"
    "litellm-route.json"
)

# Wait for APISIX admin API
wait_for_apisix() {
    log_info "Waiting for APISIX admin API..."
    for i in {1..30}; do
        if curl -s -f "$ADMIN_API/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; then
            log_success "APISIX admin API is ready"
            return 0
        fi
        sleep 2
    done
    log_error "APISIX admin API failed to become ready"
    return 1
}

# Load a route from JSON file
load_route() {
    local route_file="$1"
    local route_path="$ROUTES_DIR/$route_file"

    if [ ! -f "$route_path" ]; then
        log_error "Route file not found: $route_path"
        return 1
    fi

    local route_id
    route_id="$(jq -r '.id // empty' "$route_path" 2>/dev/null || true)"

    log_info "Loading route: $route_file"

    local payload response http_code body
    payload="$(envsubst < "$route_path")"

    if [ -n "$route_id" ]; then
        response="$(curl -sS -w "\n%{http_code}" -X PUT "$ADMIN_API/routes/$route_id" \
            -H "Content-Type: application/json" \
            -H "X-API-KEY: $ADMIN_KEY" \
            -d "$payload")"
    else
        response="$(curl -sS -w "\n%{http_code}" -X POST "$ADMIN_API/routes" \
            -H "Content-Type: application/json" \
            -H "X-API-KEY: $ADMIN_KEY" \
            -d "$payload")"
    fi

    http_code="$(tail -n1 <<<"$response")"
    body="$(sed '$d' <<<"$response")"

    if [[ "$http_code" =~ ^(200|201)$ ]]; then
        log_success "Loaded route: $route_file"
        return 0
    else
        log_error "Failed to load route: $route_file (HTTP $http_code)"
        echo "$body" >&2
        return 1
    fi
}


# Main bootstrap process
main() {
    log_info "Bootstrapping APISIX routes for $ENVIRONMENT environment..."

    # Ensure we're in the project root
    cd "$PROJECT_ROOT"

    # Wait for APISIX to be ready
    if ! wait_for_apisix; then
        exit 1
    fi

    # Load core routes
    log_info "Loading core routes..."
    local core_success=0
    for route in "${CORE_ROUTES[@]}"; do
        if load_route "$route"; then
            core_success=$((core_success + 1))
        fi
    done

    log_info "Loaded $core_success/${#CORE_ROUTES[@]} core routes"

    # Load provider routes if API keys are available
    if [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${LITELLM_KEY:-}" ]; then
        log_info "Loading provider routes (API keys detected)..."
        local provider_success=0
        for route in "${PROVIDER_ROUTES[@]}"; do
            if load_route "$route"; then
                provider_success=$((provider_success + 1))
            fi
        done
        log_info "Loaded $provider_success/${#PROVIDER_ROUTES[@]} provider routes"
    else
        log_info "Skipping provider routes (no API keys found)"
    fi

    log_success "Bootstrap completed for $ENVIRONMENT environment"
}

# Run main function
main "$@"