#!/bin/bash
# Self-contained baseline verification script
# Tests core functionality to ensure system is working properly
# Can be run independently for comparison during deployment phases

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; ((TESTS_PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; ((TESTS_FAILED++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

test_start() {
    echo -e "${BLUE}[TEST]${NC} $*";
    ((TESTS_TOTAL++));
}

# Setup environment (self-contained)
setup_environment() {
    log_info "Setting up environment..."

    # Load project environment
    if [[ -f "scripts/core/environment.sh" ]]; then
        source scripts/core/environment.sh
        setup_environment "entraid" "dev" 2>/dev/null || true
    fi

    # Set required environment variables explicitly
    export ADMIN_KEY=205cd2775b5c465657b200516fa4fce5e11487b12e3cb8bb
    export TEST_API_KEY=test-key-12345

    log_info "Environment configured"
    log_info "Admin key: ${ADMIN_KEY:0:8}..."
    log_info "Test API key: ${TEST_API_KEY}"
}

# Test functions
test_admin_api() {
    test_start "Admin API accessibility (localhost only)"

    local status
    status=$(curl -sS -o /dev/null -w "%{http_code}" \
        -H "X-API-KEY: $ADMIN_KEY" \
        http://localhost:9180/apisix/admin/routes 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]]; then
        log_success "Admin API responds with 200"
    else
        log_fail "Admin API failed with status: $status"
    fi
}

test_portal_health() {
    test_start "Portal backend health check"

    local status
    status=$(curl -sS -o /dev/null -w "%{http_code}" \
        http://localhost:3001/health 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]]; then
        log_success "Portal backend healthy (200)"
    else
        log_fail "Portal backend unhealthy, status: $status"
    fi
}

test_oidc_redirect() {
    test_start "OIDC authentication flow"

    local status
    status=$(curl -sS -o /dev/null -w "%{http_code}" \
        -X GET http://localhost:9080/portal/ 2>/dev/null || echo "000")

    if [[ "$status" == "302" ]]; then
        log_success "OIDC redirects properly (302)"
    else
        log_fail "OIDC redirect failed, status: $status"
    fi
}

test_anthropic_api() {
    test_start "Anthropic AI provider route (end-to-end)"

    local response
    response=$(curl -sS -X POST http://localhost:9080/v1/providers/anthropic/chat \
        -H "Content-Type: application/json" \
        -H "apikey: $TEST_API_KEY" \
        -d '{
            "model": "claude-3-haiku-20240307",
            "messages": [{"role": "user", "content": "Hello"}],
            "max_tokens": 5
        }' \
        -w "|%{http_code}" \
        -m 30 2>/dev/null || echo "error|000")

    local body="${response%|*}"
    local status="${response##*|}"

    if [[ "$status" == "200" ]] && echo "$body" | grep -q '"content"'; then
        log_success "Anthropic API fully functional (200, valid response)"
    else
        log_fail "Anthropic API failed - Status: $status, Response: ${body:0:100}"
    fi
}

test_api_key_auth() {
    test_start "API key authentication enforcement"

    # Test without API key (should fail)
    local status_no_key
    status_no_key=$(curl -sS -o /dev/null -w "%{http_code}" \
        -X POST http://localhost:9080/v1/providers/anthropic/chat \
        -H "Content-Type: application/json" \
        -d '{"model": "test", "messages": []}' \
        2>/dev/null || echo "000")

    # Test with wrong API key (should fail)
    local status_wrong_key
    status_wrong_key=$(curl -sS -o /dev/null -w "%{http_code}" \
        -X POST http://localhost:9080/v1/providers/anthropic/chat \
        -H "Content-Type: application/json" \
        -H "apikey: invalid-key" \
        -d '{"model": "test", "messages": []}' \
        2>/dev/null || echo "000")

    if [[ "$status_no_key" == "401" ]] && [[ "$status_wrong_key" == "401" ]]; then
        log_success "API key authentication properly enforced (both 401)"
    else
        log_fail "API key auth issues - No key: $status_no_key, Wrong key: $status_wrong_key"
    fi
}

test_docker_services() {
    test_start "Docker services status"

    local services=("portal-backend-dev" "apisix-dev" "etcd-dev")
    local all_healthy=true

    for service in "${services[@]}"; do
        if docker ps --format '{{.Names}} {{.Status}}' | grep -q "$service"; then
            if docker ps --format '{{.Names}} {{.Status}}' | grep "$service" | grep -q "healthy"; then
                log_info "  ✓ $service: healthy"
            else
                log_warn "  ✗ $service: running but not healthy"
                all_healthy=false
            fi
        else
            log_warn "  ✗ $service: not running"
            all_healthy=false
        fi
    done

    if [[ "$all_healthy" == "true" ]]; then
        log_success "All core services healthy"
    else
        log_fail "Some services not healthy"
    fi
}

# Test suite execution
main() {
    echo "=================================="
    echo "APISIX Gateway Baseline Test Suite"
    echo "=================================="
    echo "Date: $(date)"
    echo ""

    setup_environment
    echo ""

    # Run all tests
    test_docker_services
    test_admin_api
    test_portal_health
    test_oidc_redirect
    test_api_key_auth
    test_anthropic_api

    echo ""
    echo "=================================="
    echo "Test Results Summary"
    echo "=================================="
    echo "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ ALL TESTS PASSED - System is healthy!${NC}"
        exit 0
    else
        echo -e "${RED}❌ $TESTS_FAILED test(s) failed - System has issues${NC}"
        exit 1
    fi
}

# Run test suite
main "$@"