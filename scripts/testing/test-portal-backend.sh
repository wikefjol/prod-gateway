#!/bin/bash
# Portal Backend API Testing Script
# Focused testing for portal backend endpoints with immediate feedback

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BASE_URL="http://localhost:3001"
TEST_USER_OID="test-portal-$(date +%s)"
TEST_USER_NAME="Portal Test User"
TEST_USER_EMAIL="portal-test@example.com"
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

Portal Backend API Testing Script

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output including response bodies
    -u, --user ID   Use specific test user ID (default: auto-generated)

TESTS:
    1. Health check endpoint
    2. Portal dashboard without authentication (should fail)
    3. Portal dashboard with authentication
    4. Get API key operation
    5. Recycle API key operation
    6. Development admin routes (if DEV_MODE enabled)

PREREQUISITES:
    - Portal backend running on $BASE_URL
    - ADMIN_KEY environment variable set
    - For dev admin tests: DEV_MODE=true and DEV_ADMIN_PASSWORD set

EXAMPLES:
    $0                     # Run all tests with auto-generated user
    $0 -v                  # Run tests with verbose output
    $0 --user test-123     # Run tests with specific user ID
EOF
}

# Parse arguments
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
        -u|--user)
            TEST_USER_OID="$2"
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
    local path="$2"
    local headers="$3"
    local body="${4:-}"
    local expected_status="${5:-200}"

    local curl_args=("-s" "-w" "\\n%{http_code}\\n%{time_total}" "-X" "$method")

    # Add headers
    if [[ -n "$headers" ]]; then
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                curl_args+=("-H" "$key: $value")
            fi
        done <<< "$headers"
    fi

    # Add body if provided
    if [[ -n "$body" ]]; then
        curl_args+=("-d" "$body")
    fi

    # Make request
    local response
    response=$(curl "${curl_args[@]}" "$BASE_URL$path" 2>/dev/null)

    # Parse response
    local response_body
    local status_code
    local response_time
    response_body=$(echo "$response" | head -n -2)
    status_code=$(echo "$response" | tail -n 2 | head -n 1)
    response_time=$(echo "$response" | tail -n 1)

    # Show request details if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        echo "  Request: $method $BASE_URL$path"
        if [[ -n "$headers" ]]; then
            echo "  Headers: $headers"
        fi
        if [[ -n "$body" ]]; then
            echo "  Body: $body"
        fi
        echo "  Response ($status_code, ${response_time}s): $response_body"
        echo
    fi

    # Check status code
    if [[ "$status_code" == "$expected_status" ]]; then
        return 0
    else
        log_error "Expected status $expected_status, got $status_code"
        if [[ "$VERBOSE" == "false" ]]; then
            echo "  Response: $response_body"
        fi
        return 1
    fi
}

# Individual test functions
test_health_check() {
    log_test "Testing health check endpoint..."

    if make_request "GET" "/health" "" "" "200"; then
        log_success "✓ Health check passed"
        return 0
    else
        log_error "✗ Health check failed"
        return 1
    fi
}

test_portal_dashboard_no_auth() {
    log_test "Testing portal dashboard without authentication..."

    if make_request "GET" "/portal/" "" "" "401"; then
        log_success "✓ Portal correctly rejects unauthenticated requests"
        return 0
    else
        log_error "✗ Portal should reject unauthenticated requests with 401"
        return 1
    fi
}

test_portal_dashboard_with_auth() {
    log_test "Testing portal dashboard with authentication..."

    local headers="X-User-Oid=$TEST_USER_OID
X-User-Name=$TEST_USER_NAME
X-User-Email=$TEST_USER_EMAIL"

    if make_request "GET" "/portal/" "$headers" "" "200"; then
        log_success "✓ Portal dashboard loads with authentication"
        return 0
    else
        log_error "✗ Portal dashboard failed to load with authentication"
        return 1
    fi
}

test_get_api_key() {
    log_test "Testing get API key operation..."

    local headers="X-User-Oid=$TEST_USER_OID
X-User-Name=$TEST_USER_NAME
X-User-Email=$TEST_USER_EMAIL
Content-Type=application/json"

    if make_request "POST" "/portal/get-key" "$headers" "" "200"; then
        log_success "✓ Get API key operation successful"
        return 0
    else
        log_error "✗ Get API key operation failed"
        return 1
    fi
}

test_recycle_api_key() {
    log_test "Testing recycle API key operation..."

    local headers="X-User-Oid=$TEST_USER_OID
X-User-Name=$TEST_USER_NAME
X-User-Email=$TEST_USER_EMAIL
Content-Type=application/json"

    if make_request "POST" "/portal/recycle-key" "$headers" "" "200"; then
        log_success "✓ Recycle API key operation successful"
        return 0
    else
        log_error "✗ Recycle API key operation failed"
        return 1
    fi
}

test_dev_admin_routes() {
    log_test "Testing development admin routes..."

    if [[ "${DEV_MODE:-false}" != "true" ]]; then
        log_warning "⚠ DEV_MODE not enabled, skipping development admin tests"
        return 0
    fi

    # Test admin dashboard access
    if make_request "GET" "/dev/admin/" "" "" "200"; then
        log_success "✓ Development admin dashboard accessible"
    else
        log_error "✗ Development admin dashboard failed"
        return 1
    fi

    # Test user simulation with authentication
    if [[ -n "${DEV_ADMIN_PASSWORD:-}" ]]; then
        local auth_header="Authorization=Bearer $DEV_ADMIN_PASSWORD"

        if make_request "POST" "/dev/admin/simulate-user/dev-user-123" "$auth_header" "" "200"; then
            log_success "✓ Development user simulation successful"
        else
            log_error "✗ Development user simulation failed"
            return 1
        fi

        if make_request "POST" "/dev/admin/test-user/dev-user-123/get-key" "$auth_header" "" "200"; then
            log_success "✓ Development test get-key successful"
        else
            log_error "✗ Development test get-key failed"
            return 1
        fi
    else
        log_warning "⚠ DEV_ADMIN_PASSWORD not set, skipping authenticated admin tests"
    fi

    return 0
}

# Cleanup function
cleanup_test_user() {
    if [[ -n "${ADMIN_KEY:-}" ]]; then
        log_info "Cleaning up test user: $TEST_USER_OID"

        curl -s -X DELETE \
             -H "X-API-KEY: $ADMIN_KEY" \
             "http://localhost:9180/apisix/admin/consumers/$TEST_USER_OID" \
             >/dev/null 2>&1 || true

        log_info "Cleanup completed"
    fi
}

# Main test execution
main() {
    log_info "Starting Portal Backend API Tests"
    log_info "Base URL: $BASE_URL"
    log_info "Test User: $TEST_USER_OID"
    echo

    # Pre-flight checks
    log_info "Performing pre-flight checks..."

    if ! curl -s -f "$BASE_URL/health" >/dev/null; then
        log_error "Portal backend is not accessible at $BASE_URL"
        log_error "Please ensure the portal backend is running"
        exit 1
    fi

    if [[ -z "${ADMIN_KEY:-}" ]]; then
        log_warning "ADMIN_KEY not set - cleanup may not work properly"
    fi

    log_success "Pre-flight checks passed"
    echo

    # Set up cleanup trap
    trap cleanup_test_user EXIT

    # Run tests
    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    # Test 1: Health check
    total_tests=$((total_tests + 1))
    if test_health_check; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 2: Portal dashboard without auth
    total_tests=$((total_tests + 1))
    if test_portal_dashboard_no_auth; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 3: Portal dashboard with auth
    total_tests=$((total_tests + 1))
    if test_portal_dashboard_with_auth; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 4: Get API key
    total_tests=$((total_tests + 1))
    if test_get_api_key; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 5: Recycle API key
    total_tests=$((total_tests + 1))
    if test_recycle_api_key; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    echo

    # Test 6: Development admin routes (if enabled)
    if [[ "${DEV_MODE:-false}" == "true" ]]; then
        total_tests=$((total_tests + 1))
        if test_dev_admin_routes; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
        fi
        echo
    fi

    # Final summary
    log_info "=== TEST SUMMARY ==="
    log_info "Total Tests: $total_tests"
    log_success "Passed: $passed_tests"

    if [[ $failed_tests -gt 0 ]]; then
        log_error "Failed: $failed_tests"
        log_error "Success Rate: $(( passed_tests * 100 / total_tests ))%"
        echo
        log_error "Some tests failed. Check the output above for details."
        exit 1
    else
        log_success "Failed: $failed_tests"
        log_success "Success Rate: 100%"
        echo
        log_success "All tests passed successfully! 🎉"
        exit 0
    fi
}

# Execute main function
main "$@"