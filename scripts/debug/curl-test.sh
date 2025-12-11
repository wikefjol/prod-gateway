#!/bin/bash
# OIDC Flow Testing Script
# Tests various OIDC endpoints and flows

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load and ensure environment (centralized DRY pattern)
if [[ -f "$PROJECT_ROOT/scripts/core/environment.sh" ]]; then
    # shellcheck source=../core/environment.sh
    source "$PROJECT_ROOT/scripts/core/environment.sh"
    ensure_environment
else
    # Fallback logging functions
    log_info() { echo "ℹ️  $*"; }
    log_success() { echo "✅ $*"; }
    log_warning() { echo "⚠️  $*"; }
    log_error() { echo "❌ $*" >&2; }
    log_error "Environment functions not available - some features may not work"
fi

# Configuration from environment
APISIX_ADMIN_API="${APISIX_ADMIN_API:-http://apisix-dev:9180/apisix/admin}"
DATA_PLANE="${DATA_PLANE:-http://apisix-dev:9080}"
ADMIN_KEY="${ADMIN_KEY:-b690a22de520f12fd9615ab43a443b5aa7239d7153ca2850}"

# Test functions
test_discovery_endpoint() {
    log_info "Testing OIDC Discovery Endpoint"
    echo "Endpoint: $OIDC_DISCOVERY_ENDPOINT"
    echo ""

    if curl -v -f -s "$OIDC_DISCOVERY_ENDPOINT" | jq . 2>/dev/null; then
        log_success "Discovery endpoint is accessible and returns valid JSON"
    else
        log_error "Discovery endpoint test failed"
        return 1
    fi
    echo ""
}

test_apisix_admin() {
    log_info "Testing APISIX Admin API"
    echo "Admin API: $APISIX_ADMIN_API"
    echo ""

    local response
    if response=$(curl -s -H "X-API-KEY: $ADMIN_KEY" "$APISIX_ADMIN_API/routes" 2>/dev/null); then
        echo "Routes:"
        echo "$response" | jq -r '.list[]? | "\(.value.id): \(.value.uri)"' 2>/dev/null || echo "$response"
        log_success "APISIX Admin API is accessible"
    else
        log_error "APISIX Admin API test failed"
        return 1
    fi
    echo ""
}

test_portal_route() {
    log_info "Testing Portal Route"
    echo "Portal URL: $DATA_PLANE/portal/"
    echo ""

    local http_code location
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$DATA_PLANE/portal/" 2>/dev/null || echo "000")
    location=$(curl -s -I "$DATA_PLANE/portal/" 2>/dev/null | grep -i "^location:" | cut -d' ' -f2- | tr -d '\r' || echo "")

    case "$http_code" in
        "302"|"301")
            log_success "Portal route is working (redirect to OIDC provider)"
            echo "HTTP Code: $http_code"
            echo "Location: $location"
            ;;
        "200")
            log_warning "Portal route returns 200 (may not be configured for OIDC)"
            echo "HTTP Code: $http_code"
            ;;
        "404")
            log_error "Portal route not found (404)"
            echo "HTTP Code: $http_code"
            ;;
        *)
            log_error "Portal route test failed"
            echo "HTTP Code: $http_code"
            ;;
    esac
    echo ""
}

test_apisix_health() {
    log_info "Testing APISIX Health"
    echo "Health URL: $APISIX_ADMIN_API/routes (built-in admin endpoint)"
    echo ""

    if curl -f -s -H "X-API-KEY: $ADMIN_KEY" "$APISIX_ADMIN_API/routes" >/dev/null 2>&1; then
        log_success "APISIX is healthy (admin API responsive)"
    else
        log_error "APISIX health check failed"
        return 1
    fi
    echo ""
}

test_provider_specific() {
    case "${OIDC_PROVIDER_NAME:-}" in
        "keycloak")
            test_keycloak_health
            ;;
        "entraid")
            test_entraid_config
            ;;
        *)
            log_info "No provider-specific tests for: ${OIDC_PROVIDER_NAME:-unknown}"
            ;;
    esac
}

test_keycloak_health() {
    log_info "Testing Keycloak Health"
    local keycloak_url="http://keycloak-dev:8080"
    echo "Keycloak URL: $keycloak_url"
    echo ""

    if curl -f -s "$keycloak_url/health/ready" >/dev/null 2>&1; then
        log_success "Keycloak is healthy"
    else
        log_error "Keycloak health check failed"
        return 1
    fi
    echo ""
}

test_entraid_config() {
    log_info "Testing EntraID Configuration"
    echo "Discovery: $OIDC_DISCOVERY_ENDPOINT"
    echo "Client ID: $OIDC_CLIENT_ID"
    echo ""

    # Check for placeholder values
    if [[ "$OIDC_CLIENT_ID" == *"placeholder"* ]]; then
        log_warning "EntraID client ID contains placeholder value"
        log_warning "Update secrets/entraid-dev.env with actual credentials"
    else
        log_success "EntraID configuration appears to be set"
    fi

    # Test tenant ID in discovery endpoint
    if [[ "$OIDC_DISCOVERY_ENDPOINT" =~ placeholder-tenant-id ]]; then
        log_warning "EntraID tenant ID contains placeholder value"
    fi
    echo ""
}

# Network diagnostics
test_network_connectivity() {
    log_info "Testing Network Connectivity"

    local services=("apisix-dev:9080" "apisix-dev:9180" "etcd-dev:2379")

    # Add provider-specific services
    case "${OIDC_PROVIDER_NAME:-}" in
        "keycloak")
            services+=("keycloak-dev:8080")
            ;;
    esac

    for service in "${services[@]}"; do
        local host port
        IFS=':' read -r host port <<< "$service"

        if nc -z "$host" "$port" 2>/dev/null; then
            log_success "✓ $service"
        else
            log_error "✗ $service"
        fi
    done
    echo ""
}

# Full test suite
run_full_test() {
    echo "🧪 APISIX OIDC Test Suite"
    echo "========================"
    echo "Provider: ${OIDC_PROVIDER_NAME:-unknown}"
    echo "Environment: ${ENVIRONMENT:-unknown}"
    echo ""

    local failed_tests=0

    # Core tests
    test_apisix_health || ((failed_tests++))
    test_network_connectivity || ((failed_tests++))
    test_apisix_admin || ((failed_tests++))

    # OIDC tests
    if [[ -n "${OIDC_DISCOVERY_ENDPOINT:-}" ]]; then
        test_discovery_endpoint || ((failed_tests++))
        test_portal_route || ((failed_tests++))
    else
        log_warning "No OIDC_DISCOVERY_ENDPOINT set, skipping OIDC tests"
    fi

    # Provider-specific tests
    test_provider_specific || ((failed_tests++))

    echo "========================"
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All tests passed! 🎉"
        return 0
    else
        log_error "$failed_tests test(s) failed"
        return 1
    fi
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [TEST]

Run OIDC flow tests for APISIX Gateway.

TESTS:
    discovery       Test OIDC discovery endpoint
    admin          Test APISIX admin API
    portal         Test portal route
    health         Test APISIX health
    network        Test network connectivity
    provider       Test provider-specific endpoints
    all            Run all tests (default)

EXAMPLES:
    $0              # Run all tests
    $0 discovery    # Test only discovery endpoint
    $0 portal       # Test only portal route

EOF
}

# Main execution
main() {
    local test_name="${1:-all}"

    case "$test_name" in
        "discovery")
            test_discovery_endpoint
            ;;
        "admin")
            test_apisix_admin
            ;;
        "portal")
            test_portal_route
            ;;
        "health")
            test_apisix_health
            ;;
        "network")
            test_network_connectivity
            ;;
        "provider")
            test_provider_specific
            ;;
        "all")
            run_full_test
            ;;
        "-h"|"--help")
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown test: $test_name"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"