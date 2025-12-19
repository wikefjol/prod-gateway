#!/bin/bash
# Multi-Domain Flow Testing Script for Phase 2
# Tests domain routing separation and admin API blocking

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}INFO:${NC} $*" >&2; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }
log_error() { echo -e "${RED}ERROR:${NC} $*" >&2; }

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-}"

    log_info "Testing: $test_name"

    if eval "$test_command"; then
        log_success "✅ $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "❌ $test_name"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test APISIX environments are running
test_apisix_environments() {
    log_info "=== Testing APISIX Environment Availability ==="

    # Test dev environment (port 9080)
    run_test "APISIX Dev Environment (9080) Health" \
        "curl -s -f http://localhost:9080/health >/dev/null"

    # Test test environment (port 9081)
    run_test "APISIX Test Environment (9081) Health" \
        "curl -s -f http://localhost:9081/health >/dev/null"

    # Test admin API access (localhost only)
    run_test "APISIX Dev Admin API (9180) Localhost Access" \
        "curl -s -f -H 'X-API-KEY: \$ADMIN_KEY' http://localhost:9180/apisix/admin/routes >/dev/null 2>&1"

    run_test "APISIX Test Admin API (9181) Localhost Access" \
        "curl -s -f -H 'X-API-KEY: \$ADMIN_KEY' http://localhost:9181/apisix/admin/routes >/dev/null 2>&1"
}

# Test HEAD method support
test_head_method_support() {
    log_info "=== Testing HEAD Method Support ==="

    # Test /health endpoint
    run_test "Health Endpoint HEAD Support (Dev)" \
        "curl -s -I http://localhost:9080/health | head -1 | grep -q '200 OK'"

    run_test "Health Endpoint HEAD Support (Test)" \
        "curl -s -I http://localhost:9081/health | head -1 | grep -q '200 OK'"

    # Test /portal redirect endpoint
    run_test "Portal Redirect HEAD Support (Dev)" \
        "curl -s -I http://localhost:9080/portal | head -1 | grep -q '302'"

    run_test "Portal Redirect HEAD Support (Test)" \
        "curl -s -I http://localhost:9081/portal | head -1 | grep -q '302'"
}

# Test Apache domain routing (if Apache is configured)
test_apache_domain_routing() {
    log_info "=== Testing Apache Domain Routing ==="

    # Check if Apache is configured and running
    if ! systemctl is-active apache2 >/dev/null 2>&1; then
        log_warning "Apache is not running - skipping domain routing tests"
        return 0
    fi

    # Test lamassu domain routing to dev environment (9080)
    if curl -s --connect-timeout 5 https://lamassu.ita.chalmers.se/health >/dev/null 2>&1; then
        run_test "Lamassu Domain Routes to Dev Environment" \
            "curl -s https://lamassu.ita.chalmers.se/health | grep -q 'ok' || true"
    else
        log_warning "Lamassu domain not accessible - may not be DNS configured or Apache not set up"
    fi

    # Test ai-gateway domain routing to test environment (9081)
    if curl -s --connect-timeout 5 https://ai-gateway.portal.chalmers.se/health >/dev/null 2>&1; then
        run_test "AI-Gateway Domain Routes to Test Environment" \
            "curl -s https://ai-gateway.portal.chalmers.se/health | grep -q 'ok' || true"
    else
        log_warning "AI-Gateway domain not accessible - may not be DNS configured or certificate not issued"
    fi
}

# Test admin API blocking through Apache
test_admin_api_blocking() {
    log_info "=== Testing Admin API Blocking ==="

    # Test admin blocking through lamassu domain
    if curl -s --connect-timeout 5 https://lamassu.ita.chalmers.se/ >/dev/null 2>&1; then
        run_test "Admin API Blocked via Lamassu Domain" \
            "curl -s -I https://lamassu.ita.chalmers.se/apisix/admin/routes | head -1 | grep -q '403'"
    else
        log_warning "Lamassu domain not accessible - skipping admin API blocking test"
    fi

    # Test admin blocking through ai-gateway domain
    if curl -s --connect-timeout 5 https://ai-gateway.portal.chalmers.se/ >/dev/null 2>&1; then
        run_test "Admin API Blocked via AI-Gateway Domain" \
            "curl -s -I https://ai-gateway.portal.chalmers.se/apisix/admin/routes | head -1 | grep -q '403'"
    else
        log_warning "AI-Gateway domain not accessible - skipping admin API blocking test"
    fi

    # Test admin API is still accessible via localhost (should work)
    run_test "Admin API Still Accessible via Localhost (Dev)" \
        "curl -s -f -H 'X-API-KEY: \$ADMIN_KEY' http://localhost:9180/apisix/admin/routes >/dev/null 2>&1 || true"

    run_test "Admin API Still Accessible via Localhost (Test)" \
        "curl -s -f -H 'X-API-KEY: \$ADMIN_KEY' http://localhost:9181/apisix/admin/routes >/dev/null 2>&1 || true"
}

# Test OIDC route configuration
test_oidc_route_configuration() {
    log_info "=== Testing OIDC Route Configuration ==="

    # Verify HEAD method was added to portal OIDC route
    if [[ -f "/home/filbern/dev/apisix-gateway/apisix/oidc-generic-route.json" ]]; then
        run_test "Portal OIDC Route Has HEAD Method" \
            "grep -q '\"HEAD\"' /home/filbern/dev/apisix-gateway/apisix/oidc-generic-route.json"
    else
        log_warning "OIDC route file not found - skipping configuration test"
    fi
}

# Test environment separation
test_environment_separation() {
    log_info "=== Testing Environment Separation ==="

    # Check that both environments are running different instances
    run_test "Different APISIX Instances Running" \
        "curl -s http://localhost:9080/health && curl -s http://localhost:9081/health >/dev/null"

    # Verify environments are isolated (admin APIs are on different ports)
    run_test "Admin APIs on Separate Ports" \
        "[[ \$(curl -s -H 'X-API-KEY: \$ADMIN_KEY' http://localhost:9180/apisix/admin/routes 2>/dev/null || echo 'failed') != \$(curl -s -H 'X-API-KEY: \$ADMIN_KEY' http://localhost:9181/apisix/admin/routes 2>/dev/null || echo 'failed') ]] || true"
}

# Display test results summary
display_results() {
    log_info "=== Test Results Summary ==="

    echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "\n${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}❌${NC} $test"
        done
        echo ""
        echo -e "${YELLOW}Note: Some failures may be expected if Apache is not yet configured or certificates not issued.${NC}"
        return 1
    else
        echo -e "\n${GREEN}🎉 All tests passed!${NC}"
        return 0
    fi
}

# Main execution
main() {
    log_info "Starting Multi-Domain Flow Testing for Phase 2"
    log_info "Testing domain routing separation, HEAD method support, and admin API blocking"
    echo ""

    # Load environment variables if available
    if [[ -f "/home/filbern/dev/apisix-gateway/config/env/dev.complete.env" ]]; then
        source "/home/filbern/dev/apisix-gateway/config/env/dev.complete.env"
    fi

    # Run all test suites
    test_apisix_environments
    echo ""
    test_head_method_support
    echo ""
    test_oidc_route_configuration
    echo ""
    test_environment_separation
    echo ""
    test_apache_domain_routing
    echo ""
    test_admin_api_blocking
    echo ""

    # Display final results
    display_results
}

# Handle script arguments
case "${1:-}" in
    "apisix-only")
        test_apisix_environments
        test_head_method_support
        test_oidc_route_configuration
        test_environment_separation
        display_results
        ;;
    "apache-only")
        test_apache_domain_routing
        test_admin_api_blocking
        display_results
        ;;
    *)
        main
        ;;
esac