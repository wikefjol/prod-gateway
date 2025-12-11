#!/bin/bash
# OIDC Flow Integration Testing Script
# Tests OIDC authentication flow and APISIX integration

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source core environment functions
# shellcheck source=../core/environment.sh
source "$SCRIPT_DIR/../core/environment.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APISIX_GATEWAY="http://localhost:9080"
APISIX_ADMIN="http://localhost:9180"
VERBOSE=false

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OIDC Flow Integration Testing Script

OPTIONS:
    -h, --help         Show this help message
    -v, --verbose      Enable verbose output including response details
    -p, --provider     Test specific provider (entraid, keycloak, auto)

TESTS:
    1. APISIX gateway connectivity
    2. APISIX Admin API access
    3. OIDC discovery endpoint accessibility
    4. Portal route OIDC redirect behavior
    5. Route configuration validation
    6. Provider-specific tests

PREREQUISITES:
    - APISIX gateway running on $APISIX_GATEWAY
    - APISIX Admin API running on $APISIX_ADMIN
    - Environment variables: ADMIN_KEY, OIDC_PROVIDER_NAME, OIDC_DISCOVERY_ENDPOINT
    - OIDC provider accessible (EntraID or Keycloak)

EXAMPLES:
    $0                          # Run all OIDC flow tests
    $0 -v                       # Run tests with verbose output
    $0 --provider entraid       # Test EntraID-specific behavior
EOF
}

# Parse arguments
PROVIDER_FILTER="auto"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -p|--provider)
            PROVIDER_FILTER="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Test helper functions
make_request() {
    local method="$1"
    local url="$2"
    local headers="$3"
    local expected_pattern="${4:-}"
    local timeout="${5:-10}"
    local follow_redirects="${6:-true}"

    local curl_args=("-s" "-w" "\\n%{http_code}\\n%{time_total}\\n%{redirect_url}" "-X" "$method" "--connect-timeout" "$timeout")

    # Handle redirects
    if [[ "$follow_redirects" == "false" ]]; then
        curl_args+=("--max-redirs" "0")
    fi

    # Add headers
    if [[ -n "$headers" ]]; then
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                curl_args+=("-H" "$key: $value")
            fi
        done <<< "$headers"
    fi

    # Make request
    local response
    response=$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo -e "\\nERROR\\n0\\n")

    # Parse response
    local response_body
    local status_code
    local response_time
    local redirect_url
    response_body=$(echo "$response" | head -n -3)
    status_code=$(echo "$response" | tail -n 3 | head -n 1)
    response_time=$(echo "$response" | tail -n 2 | head -n 1)
    redirect_url=$(echo "$response" | tail -n 1)

    # Show request details if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        echo "  Request: $method $url"
        if [[ -n "$headers" ]]; then
            echo "  Headers: $headers"
        fi
        echo "  Response ($status_code, ${response_time}s):"
        if [[ -n "$redirect_url" && "$redirect_url" != "$url" ]]; then
            echo "  Redirect: $redirect_url"
        fi
        echo "  Body: ${response_body:0:200}${#response_body -gt 200 && echo '...'}"
        echo
    fi

    # Store results in global variables for test functions
    LAST_RESPONSE_BODY="$response_body"
    LAST_STATUS_CODE="$status_code"
    LAST_REDIRECT_URL="$redirect_url"

    # Check expected pattern if provided
    if [[ -n "$expected_pattern" ]]; then
        if echo "$response_body" | grep -q "$expected_pattern" || \
           echo "$redirect_url" | grep -q "$expected_pattern" || \
           [[ "$status_code" == "$expected_pattern" ]]; then
            return 0
        else
            return 1
        fi
    fi

    return 0
}

# Individual test functions
test_apisix_connectivity() {
    log_test "Testing APISIX gateway connectivity..."

    # APISIX returns 404 for unknown routes, which indicates it's running
    if make_request "GET" "$APISIX_GATEWAY/nonexistent-route" "" "404" 5; then
        log_success "✓ APISIX gateway is responding"
        return 0
    elif [[ "$LAST_STATUS_CODE" == "ERROR" ]]; then
        log_error "✗ APISIX gateway is not accessible at $APISIX_GATEWAY"
        return 1
    else
        log_success "✓ APISIX gateway is responding (status: $LAST_STATUS_CODE)"
        return 0
    fi
}

test_apisix_admin_api() {
    log_test "Testing APISIX Admin API access..."

    if [[ -z "${ADMIN_KEY:-}" ]]; then
        log_error "✗ ADMIN_KEY environment variable not set"
        return 1
    fi

    local admin_headers="X-API-KEY=$ADMIN_KEY"

    if make_request "GET" "$APISIX_ADMIN/apisix/admin/routes" "$admin_headers" "200"; then
        log_success "✓ APISIX Admin API is accessible with admin key"
        return 0
    else
        log_error "✗ APISIX Admin API access failed (status: $LAST_STATUS_CODE)"
        return 1
    fi
}

test_oidc_discovery_endpoint() {
    log_test "Testing OIDC discovery endpoint accessibility..."

    if [[ -z "${OIDC_DISCOVERY_ENDPOINT:-}" ]]; then
        log_error "✗ OIDC_DISCOVERY_ENDPOINT environment variable not set"
        return 1
    fi

    log_info "Testing discovery endpoint: $OIDC_DISCOVERY_ENDPOINT"

    if make_request "GET" "$OIDC_DISCOVERY_ENDPOINT" "" "authorization_endpoint" 30; then
        log_success "✓ OIDC discovery endpoint is accessible"

        # Validate discovery document structure
        if echo "$LAST_RESPONSE_BODY" | grep -q "token_endpoint" && \
           echo "$LAST_RESPONSE_BODY" | grep -q "userinfo_endpoint"; then
            log_success "✓ OIDC discovery document has required endpoints"
        else
            log_warning "⚠ OIDC discovery document may be missing required endpoints"
        fi
        return 0
    else
        log_error "✗ OIDC discovery endpoint is not accessible (status: $LAST_STATUS_CODE)"
        log_error "  This could indicate network issues or incorrect provider configuration"
        return 1
    fi
}

test_portal_route_redirect() {
    log_test "Testing portal route OIDC redirect behavior..."

    # Test portal route without following redirects
    if make_request "GET" "$APISIX_GATEWAY/portal/" "" "" 10 "false"; then
        # Check if we get a redirect status
        if [[ "$LAST_STATUS_CODE" =~ ^(301|302|307|308)$ ]]; then
            log_success "✓ Portal route returns redirect status: $LAST_STATUS_CODE"

            # Check if redirect URL contains OIDC provider
            if [[ -n "$LAST_REDIRECT_URL" ]]; then
                log_info "  Redirect URL: $LAST_REDIRECT_URL"

                if echo "$LAST_REDIRECT_URL" | grep -iE "(login\.microsoftonline\.com|keycloak|oauth|auth)" >/dev/null; then
                    log_success "✓ Redirect URL appears to be OIDC provider"
                else
                    log_warning "⚠ Redirect URL may not be OIDC provider"
                fi
            else
                log_warning "⚠ No redirect URL found in response"
            fi
            return 0
        else
            log_error "✗ Portal route should redirect to OIDC provider, got status: $LAST_STATUS_CODE"
            return 1
        fi
    else
        log_error "✗ Portal route is not accessible (status: $LAST_STATUS_CODE)"
        return 1
    fi
}

test_route_configuration() {
    log_test "Testing APISIX route configuration..."

    if [[ -z "${ADMIN_KEY:-}" ]]; then
        log_error "✗ ADMIN_KEY not available for route inspection"
        return 1
    fi

    local admin_headers="X-API-KEY=$ADMIN_KEY"

    if make_request "GET" "$APISIX_ADMIN/apisix/admin/routes" "$admin_headers" "200"; then
        log_success "✓ Retrieved APISIX routes configuration"

        # Check for portal route
        if echo "$LAST_RESPONSE_BODY" | grep -q "portal"; then
            log_success "✓ Portal route found in APISIX configuration"
        else
            log_error "✗ Portal route not found in APISIX configuration"
            return 1
        fi

        # Check for OIDC plugin
        if echo "$LAST_RESPONSE_BODY" | grep -q "openid-connect"; then
            log_success "✓ OIDC (openid-connect) plugin found in routes"
        else
            log_warning "⚠ OIDC plugin not found in route configuration"
        fi

        # Check for callback route
        if echo "$LAST_RESPONSE_BODY" | grep -q "callback"; then
            log_success "✓ OIDC callback route found in configuration"
        else
            log_warning "⚠ OIDC callback route not found"
        fi

        return 0
    else
        log_error "✗ Failed to retrieve APISIX routes (status: $LAST_STATUS_CODE)"
        return 1
    fi
}

test_provider_specific() {
    local provider="${OIDC_PROVIDER_NAME:-unknown}"

    if [[ "$PROVIDER_FILTER" != "auto" && "$PROVIDER_FILTER" != "$provider" ]]; then
        log_info "Skipping provider-specific tests (filter: $PROVIDER_FILTER, actual: $provider)"
        return 0
    fi

    log_test "Testing $provider-specific behavior..."

    case "$provider" in
        "entraid")
            test_entraid_specific
            ;;
        "keycloak")
            test_keycloak_specific
            ;;
        *)
            log_warning "⚠ Unknown provider '$provider', skipping provider-specific tests"
            return 0
            ;;
    esac
}

test_entraid_specific() {
    log_test "Testing EntraID-specific configuration..."

    # Check discovery endpoint format
    if [[ "${OIDC_DISCOVERY_ENDPOINT:-}" =~ login\.microsoftonline\.com.*v2\.0.*\.well-known ]]; then
        log_success "✓ EntraID discovery endpoint format is correct"
    else
        log_warning "⚠ EntraID discovery endpoint format may be incorrect"
        log_info "  Expected format: https://login.microsoftonline.com/{tenant}/v2.0/.well-known/openid-configuration"
        log_info "  Actual: ${OIDC_DISCOVERY_ENDPOINT:-not set}"
    fi

    # Check if tenant ID looks valid
    if [[ "${ENTRAID_TENANT_ID:-}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        log_success "✓ EntraID tenant ID format is valid"
    elif [[ -n "${ENTRAID_TENANT_ID:-}" ]]; then
        log_warning "⚠ EntraID tenant ID format may be incorrect (should be UUID format)"
    fi

    # Test EntraID discovery endpoint specifically
    if [[ -n "${OIDC_DISCOVERY_ENDPOINT:-}" ]]; then
        if make_request "GET" "$OIDC_DISCOVERY_ENDPOINT" "" "issuer" 30; then
            if echo "$LAST_RESPONSE_BODY" | grep -q "login.microsoftonline.com"; then
                log_success "✓ EntraID discovery endpoint returns Microsoft issuer"
            else
                log_warning "⚠ Discovery endpoint may not be Microsoft EntraID"
            fi
        fi
    fi

    return 0
}

test_keycloak_specific() {
    log_test "Testing Keycloak-specific configuration..."

    # Check discovery endpoint format
    if [[ "${OIDC_DISCOVERY_ENDPOINT:-}" =~ keycloak.*realms.*\.well-known ]]; then
        log_success "✓ Keycloak discovery endpoint format is correct"
    else
        log_warning "⚠ Keycloak discovery endpoint format may be incorrect"
        log_info "  Expected format: http://keycloak:8080/realms/{realm}/.well-known/openid-connect/configuration"
        log_info "  Actual: ${OIDC_DISCOVERY_ENDPOINT:-not set}"
    fi

    # Test Keycloak admin console accessibility
    log_test "Testing Keycloak admin console..."
    if make_request "GET" "http://localhost:8080/admin/" "" "" 10 "false"; then
        if [[ "$LAST_STATUS_CODE" =~ ^(200|302)$ ]]; then
            log_success "✓ Keycloak admin console is accessible"
        else
            log_warning "⚠ Keycloak admin console returned status: $LAST_STATUS_CODE"
        fi
    else
        log_warning "⚠ Keycloak admin console is not accessible (may not be running)"
    fi

    return 0
}

# Main test execution
main() {
    # Load environment first (centralized DRY pattern)
    ensure_environment

    log_info "Starting OIDC Flow Integration Tests"
    log_info "APISIX Gateway: $APISIX_GATEWAY"
    log_info "APISIX Admin: $APISIX_ADMIN"
    log_info "Provider: ${OIDC_PROVIDER_NAME:-unknown}"
    echo

    log_success "Environment loaded and validated successfully"
    echo

    # Run tests
    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    # Test 1: APISIX connectivity
    total_tests=$((total_tests + 1))
    if test_apisix_connectivity; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 2: APISIX Admin API
    total_tests=$((total_tests + 1))
    if test_apisix_admin_api; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 3: OIDC discovery endpoint
    total_tests=$((total_tests + 1))
    if test_oidc_discovery_endpoint; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 4: Portal route redirect
    total_tests=$((total_tests + 1))
    if test_portal_route_redirect; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 5: Route configuration
    total_tests=$((total_tests + 1))
    if test_route_configuration; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 6: Provider-specific tests
    total_tests=$((total_tests + 1))
    if test_provider_specific; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Final summary
    log_info "=== TEST SUMMARY ==="
    log_info "Provider: ${OIDC_PROVIDER_NAME:-unknown}"
    log_info "Total Tests: $total_tests"
    log_success "Passed: $passed_tests"

    if [[ $failed_tests -gt 0 ]]; then
        log_error "Failed: $failed_tests"
        log_error "Success Rate: $(( passed_tests * 100 / total_tests ))%"
        echo
        log_error "Some OIDC integration tests failed."
        log_error "Check OIDC provider configuration and network connectivity."
        exit 1
    else
        log_success "Failed: $failed_tests"
        log_success "Success Rate: 100%"
        echo
        log_success "All OIDC integration tests passed successfully! 🎉"

        # Provide next steps
        echo
        log_info "=== NEXT STEPS ==="
        log_info "✓ OIDC configuration appears correct"
        log_info "✓ You can test the complete flow by visiting: $APISIX_GATEWAY/portal/"
        log_info "✓ This should redirect you to ${OIDC_PROVIDER_NAME:-the OIDC provider} for authentication"
        exit 0
    fi
}

# Execute main function
main "$@"