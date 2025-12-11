#!/bin/bash
# Behavior Testing Framework - Main Orchestrator
# Executes behavior tests and compares actual vs expected outcomes

set -euo pipefail

# Get script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source core environment functions
# shellcheck source=../core/environment.sh
source "$SCRIPT_DIR/../core/environment.sh"

# Global variables
TEST_SUITE=""
TEST_RUN_ID=""
RESULTS_DIR=""
VERBOSE=false
CONTINUE_ON_FAILURE=false
GENERATE_REPORT=true
CLEANUP_ON_EXIT=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
    fi
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TEST_SUITE]

Behavior Testing Framework - Executes tests and validates expected vs actual behavior

OPTIONS:
    -h, --help                  Show this help message
    -v, --verbose              Enable verbose output
    -c, --continue-on-failure  Continue testing even if individual tests fail
    -n, --no-report           Skip generating test report
    -k, --no-cleanup          Skip cleanup on exit
    -r, --results-dir DIR      Specify custom results directory
    -i, --run-id ID           Specify custom test run ID

TEST_SUITE:
    portal-backend-api         Test portal backend API endpoints
    oidc-flow                  Test OIDC authentication flow
    consumer-management        Test APISIX Consumer management
    all                        Run all test suites (default)

EXAMPLES:
    $0                                    # Run all test suites
    $0 portal-backend-api                 # Run only portal backend tests
    $0 -v --continue-on-failure all       # Run all tests with verbose output
    $0 --no-cleanup oidc-flow            # Run OIDC tests without cleanup

ENVIRONMENT SETUP:
    Ensure the following environment variables are set:
    - ADMIN_KEY: APISIX Admin API key
    - DEV_MODE: Enable development mode for admin tests
    - DEV_ADMIN_PASSWORD: Development admin password

    Services must be running:
    - apisix-dev (APISIX Gateway)
    - etcd-dev (Configuration store)
    - portal-backend-dev (Portal backend service)

EOF
}

# Parse command line arguments
parse_arguments() {
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
            -c|--continue-on-failure)
                CONTINUE_ON_FAILURE=true
                shift
                ;;
            -n|--no-report)
                GENERATE_REPORT=false
                shift
                ;;
            -k|--no-cleanup)
                CLEANUP_ON_EXIT=false
                shift
                ;;
            -r|--results-dir)
                RESULTS_DIR="$2"
                shift 2
                ;;
            -i|--run-id)
                TEST_RUN_ID="$2"
                shift 2
                ;;
            portal-backend-api|oidc-flow|consumer-management|all)
                TEST_SUITE="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Set defaults
    TEST_SUITE="${TEST_SUITE:-all}"
    TEST_RUN_ID="${TEST_RUN_ID:-$(date +%Y-%m-%d-%H%M%S)-$$}"
    RESULTS_DIR="${RESULTS_DIR:-$PROJECT_ROOT/tests/results/$TEST_RUN_ID}"
}

# Environment validation
validate_environment() {
    log_info "Validating test environment..."

    # Load and validate environment (centralized DRY pattern)
    ensure_environment

    # Check if services are running
    local required_services=("apisix-dev" "etcd-dev" "portal-backend-dev")
    local missing_services=()

    for service in "${required_services[@]}"; do
        if ! docker ps --format "table {{.Names}}" | grep -q "^$service$"; then
            missing_services+=("$service")
        fi
    done

    if [[ ${#missing_services[@]} -gt 0 ]]; then
        log_error "Required services not running: ${missing_services[*]}"
        log_error "Please run: ./scripts/lifecycle/start.sh --provider <provider>"
        return 1
    fi

    # Test basic connectivity
    log_verbose "Testing service connectivity..."

    if ! curl -s -f "http://localhost:3001/health" >/dev/null; then
        log_error "Portal backend health check failed"
        return 1
    fi

    if ! curl -s -f -H "X-API-KEY: $ADMIN_KEY" "http://localhost:9180/apisix/admin/routes" >/dev/null; then
        log_error "APISIX Admin API connectivity failed"
        return 1
    fi

    log_success "Environment validation passed"
    return 0
}

# Create results directory structure
setup_results_directory() {
    log_info "Setting up results directory: $RESULTS_DIR"

    mkdir -p "$RESULTS_DIR"/{raw,processed,reports,artifacts}

    # Create test run metadata
    cat > "$RESULTS_DIR/test-run-metadata.json" << EOF
{
    "test_run_id": "$TEST_RUN_ID",
    "test_suite": "$TEST_SUITE",
    "start_time": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "environment": {
        "admin_key_set": $([ -n "${ADMIN_KEY:-}" ] && echo "true" || echo "false"),
        "dev_mode": "${DEV_MODE:-false}",
        "oidc_provider": "${OIDC_PROVIDER_NAME:-unknown}"
    },
    "options": {
        "verbose": $VERBOSE,
        "continue_on_failure": $CONTINUE_ON_FAILURE,
        "generate_report": $GENERATE_REPORT,
        "cleanup_on_exit": $CLEANUP_ON_EXIT
    },
    "services": {}
}
EOF

    # Capture service versions and status
    log_verbose "Capturing service information..."

    docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Image}}" \
        --filter "name=apisix-dev" --filter "name=etcd-dev" --filter "name=portal-backend-dev" \
        > "$RESULTS_DIR/artifacts/service-status.txt" 2>/dev/null || true

    log_success "Results directory setup complete"
}

# Execute a single test from JSON definition
execute_test() {
    local test_file="$1"
    local test_id="$2"
    local output_file="$3"

    log_verbose "Executing test: $test_id from $test_file"

    # Use Python to parse JSON and execute test
    python3 << EOF
import json
import sys
import requests
import subprocess
import time
from datetime import datetime

def execute_single_test():
    try:
        # Read test definition
        with open('$test_file', 'r') as f:
            test_suite = json.load(f)

        # Find the specific test
        test_case = None
        for test in test_suite.get('tests', []):
            if test.get('test_id') == '$test_id':
                test_case = test
                break

        if not test_case:
            print(json.dumps({
                "status": "error",
                "error": "Test case not found",
                "test_id": "$test_id"
            }))
            return 1

        # Execute prerequisite cleanup if defined
        if 'prerequisite_cleanup' in test_case:
            cleanup = test_case['prerequisite_cleanup']
            if 'cleanup_request' in cleanup:
                req = cleanup['cleanup_request']
                try:
                    response = requests.request(
                        method=req.get('method', 'GET'),
                        url=req['url'].replace('\${ADMIN_KEY}', '$ADMIN_KEY'),
                        headers=req.get('headers', {}),
                        json=req.get('body'),
                        timeout=req.get('timeout', 30)
                    )
                    # Ignore specified error codes
                    ignore_errors = req.get('ignore_errors', [])
                    if response.status_code not in ignore_errors and not response.ok:
                        print(f"Cleanup warning: {response.status_code}", file=sys.stderr)
                except Exception as e:
                    print(f"Cleanup error (ignored): {e}", file=sys.stderr)

        # Execute the main request
        request_data = test_case.get('request', {})

        if request_data.get('method') == 'EXEC':
            # Execute shell command
            start_time = time.time()
            try:
                result = subprocess.run(
                    request_data['command'],
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=request_data.get('timeout', 30)
                )
                end_time = time.time()

                response_data = {
                    "exit_code": result.returncode,
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "response_time_ms": int((end_time - start_time) * 1000)
                }
            except subprocess.TimeoutExpired:
                response_data = {
                    "exit_code": -1,
                    "stdout": "",
                    "stderr": "Command timed out",
                    "response_time_ms": request_data.get('timeout', 30) * 1000
                }
        else:
            # Execute HTTP request
            headers = request_data.get('headers', {})
            # Replace environment variables in headers
            for key, value in headers.items():
                if isinstance(value, str):
                    headers[key] = value.replace('\${ADMIN_KEY}', '$ADMIN_KEY')

            start_time = time.time()
            try:
                response = requests.request(
                    method=request_data.get('method', 'GET'),
                    url=request_data['url'],
                    headers=headers,
                    json=request_data.get('body'),
                    timeout=request_data.get('timeout', 30),
                    allow_redirects=request_data.get('allow_redirects', True)
                )
                end_time = time.time()

                # Try to parse JSON response
                try:
                    response_json = response.json()
                except:
                    response_json = None

                response_data = {
                    "status_code": response.status_code,
                    "headers": dict(response.headers),
                    "json": response_json,
                    "text": response.text[:1000],  # Limit response text
                    "response_time_ms": int((end_time - start_time) * 1000)
                }
            except requests.exceptions.RequestException as e:
                response_data = {
                    "status_code": 0,
                    "headers": {},
                    "json": None,
                    "text": str(e),
                    "response_time_ms": -1,
                    "error": str(e)
                }

        # Prepare test result
        result = {
            "test_id": test_case.get('test_id'),
            "name": test_case.get('name'),
            "description": test_case.get('description'),
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "request": request_data,
            "response": response_data,
            "expected": test_case.get('expected_response', {}),
            "validation_rules": test_case.get('validation_rules', []),
            "status": "unknown"
        }

        # Save result
        with open('$output_file', 'w') as f:
            json.dump(result, f, indent=2)

        return 0

    except Exception as e:
        error_result = {
            "test_id": "$test_id",
            "status": "error",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat() + 'Z'
        }
        with open('$output_file', 'w') as f:
            json.dump(error_result, f, indent=2)
        return 1

if __name__ == "__main__":
    sys.exit(execute_single_test())
EOF

    return $?
}

# Validate test results against expected behavior
validate_test_result() {
    local result_file="$1"
    local validation_file="${result_file%.json}-validation.json"

    log_verbose "Validating test result: $result_file"

    # Use Python to validate results
    python3 << EOF
import json
import sys
from datetime import datetime

def validate_result():
    try:
        # Read test result
        with open('$result_file', 'r') as f:
            result = json.load(f)

        if result.get('status') == 'error':
            # Test execution failed
            validation = {
                "test_id": result.get('test_id'),
                "validation_status": "execution_failed",
                "validation_time": datetime.utcnow().isoformat() + 'Z',
                "error": result.get('error'),
                "passed": False,
                "failed_validations": ["Test execution failed"]
            }
        else:
            # Validate against expected behavior
            response = result.get('response', {})
            expected = result.get('expected', {})
            validation_rules = result.get('validation_rules', [])

            passed_validations = []
            failed_validations = []

            # Basic status code validation
            expected_status = expected.get('status_code')
            actual_status = response.get('status_code')

            if expected_status:
                if isinstance(expected_status, list):
                    if actual_status in expected_status:
                        passed_validations.append(f"Status code {actual_status} in expected list {expected_status}")
                    else:
                        failed_validations.append(f"Status code {actual_status} not in expected list {expected_status}")
                else:
                    if actual_status == expected_status:
                        passed_validations.append(f"Status code matches expected {expected_status}")
                    else:
                        failed_validations.append(f"Status code {actual_status} != expected {expected_status}")

            # Content-type validation
            expected_content_type = expected.get('headers', {}).get('content-type')
            actual_content_type = response.get('headers', {}).get('content-type', '')

            if expected_content_type:
                if expected_content_type in actual_content_type:
                    passed_validations.append(f"Content-type contains expected '{expected_content_type}'")
                else:
                    failed_validations.append(f"Content-type '{actual_content_type}' does not contain '{expected_content_type}'")

            # Body validation for contains checks
            body_contains = expected.get('body_contains', [])
            response_text = response.get('text', '')

            for expected_text in body_contains:
                if expected_text in response_text:
                    passed_validations.append(f"Response contains expected text: '{expected_text}'")
                else:
                    failed_validations.append(f"Response does not contain expected text: '{expected_text}'")

            # JSON body field validation
            expected_body = expected.get('body', {})
            response_json = response.get('json', {})

            if expected_body and response_json:
                for key, expected_value in expected_body.items():
                    if key in response_json:
                        if response_json[key] == expected_value:
                            passed_validations.append(f"JSON field '{key}' matches expected value")
                        else:
                            failed_validations.append(f"JSON field '{key}' = {response_json[key]} != expected {expected_value}")
                    else:
                        failed_validations.append(f"JSON field '{key}' missing from response")

            validation = {
                "test_id": result.get('test_id'),
                "validation_status": "completed",
                "validation_time": datetime.utcnow().isoformat() + 'Z',
                "passed": len(failed_validations) == 0,
                "passed_validations": passed_validations,
                "failed_validations": failed_validations,
                "validation_count": {
                    "total": len(passed_validations) + len(failed_validations),
                    "passed": len(passed_validations),
                    "failed": len(failed_validations)
                }
            }

        # Save validation result
        with open('$validation_file', 'w') as f:
            json.dump(validation, f, indent=2)

        # Print validation summary
        if validation.get('passed'):
            print("PASSED")
        else:
            print("FAILED")
            if '$VERBOSE' == 'true':
                for failure in validation.get('failed_validations', []):
                    print(f"  - {failure}", file=sys.stderr)

        return 0 if validation.get('passed') else 1

    except Exception as e:
        error_validation = {
            "test_id": "unknown",
            "validation_status": "validation_error",
            "validation_time": datetime.utcnow().isoformat() + 'Z',
            "error": str(e),
            "passed": False
        }
        with open('$validation_file', 'w') as f:
            json.dump(error_validation, f, indent=2)
        print("VALIDATION_ERROR")
        return 1

if __name__ == "__main__":
    sys.exit(validate_result())
EOF

    return $?
}

# Run tests for a specific test suite
run_test_suite() {
    local suite_name="$1"
    local test_file="$PROJECT_ROOT/tests/expected-behavior/$suite_name.json"

    if [[ ! -f "$test_file" ]]; then
        log_error "Test file not found: $test_file"
        return 1
    fi

    log_info "Running test suite: $suite_name"

    # Parse test file to get list of tests
    local test_ids
    test_ids=$(python3 -c "
import json
with open('$test_file', 'r') as f:
    data = json.load(f)
for test in data.get('tests', []):
    print(test.get('test_id', ''))
")

    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    # Execute each test
    for test_id in $test_ids; do
        if [[ -z "$test_id" ]]; then
            continue
        fi

        total_tests=$((total_tests + 1))

        log_info "  Test $total_tests: $test_id"

        local result_file="$RESULTS_DIR/raw/${suite_name}-${test_id}.json"

        if execute_test "$test_file" "$test_id" "$result_file"; then
            # Validate the test result
            local validation_result
            validation_result=$(validate_test_result "$result_file")
            local validation_exit_code=$?

            if [[ $validation_exit_code -eq 0 ]]; then
                log_success "    ✓ $validation_result"
                passed_tests=$((passed_tests + 1))
            else
                log_error "    ✗ $validation_result"
                failed_tests=$((failed_tests + 1))

                if [[ "$CONTINUE_ON_FAILURE" == "false" ]]; then
                    log_error "Stopping test suite execution due to failure"
                    break
                fi
            fi
        else
            log_error "    ✗ Test execution failed"
            failed_tests=$((failed_tests + 1))

            if [[ "$CONTINUE_ON_FAILURE" == "false" ]]; then
                log_error "Stopping test suite execution due to failure"
                break
            fi
        fi
    done

    # Save suite summary
    cat > "$RESULTS_DIR/processed/${suite_name}-summary.json" << EOF
{
    "suite_name": "$suite_name",
    "total_tests": $total_tests,
    "passed_tests": $passed_tests,
    "failed_tests": $failed_tests,
    "success_rate": $(( passed_tests * 100 / (total_tests == 0 ? 1 : total_tests) )),
    "completion_time": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
}
EOF

    log_info "Test suite '$suite_name' completed: $passed_tests/$total_tests passed"

    return $((failed_tests > 0 ? 1 : 0))
}

# Generate comprehensive test report
generate_report() {
    if [[ "$GENERATE_REPORT" == "false" ]]; then
        return 0
    fi

    log_info "Generating test report..."

    local report_file="$RESULTS_DIR/reports/behavior-test-report.html"

    # Use Python to generate HTML report
    python3 << 'EOF'
import json
import os
import glob
from datetime import datetime

results_dir = os.environ['RESULTS_DIR']

# Read test run metadata
with open(f'{results_dir}/test-run-metadata.json', 'r') as f:
    metadata = json.load(f)

# Collect all test results and validations
results = []
validations = []

for result_file in glob.glob(f'{results_dir}/raw/*.json'):
    try:
        with open(result_file, 'r') as f:
            result = json.load(f)
        results.append(result)

        validation_file = result_file.replace('.json', '-validation.json')
        if os.path.exists(validation_file):
            with open(validation_file, 'r') as f:
                validation = json.load(f)
            validations.append(validation)
    except Exception as e:
        continue

# Generate HTML report
html_content = f'''<!DOCTYPE html>
<html>
<head>
    <title>Behavior Test Report - {metadata['test_run_id']}</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
        h1, h2, h3 {{ color: #333; }}
        .summary {{ background: #e9ecef; padding: 20px; border-radius: 4px; margin-bottom: 20px; }}
        .test-result {{ border: 1px solid #ddd; margin: 10px 0; border-radius: 4px; }}
        .test-passed {{ border-left: 4px solid #28a745; }}
        .test-failed {{ border-left: 4px solid #dc3545; }}
        .test-header {{ background: #f8f9fa; padding: 15px; cursor: pointer; }}
        .test-details {{ padding: 15px; display: none; }}
        .test-details.show {{ display: block; }}
        pre {{ background: #f8f9fa; padding: 10px; border-radius: 4px; overflow-x: auto; font-size: 12px; }}
        .stats {{ display: flex; gap: 20px; margin-bottom: 20px; }}
        .stat {{ text-align: center; padding: 15px; background: #fff; border: 1px solid #ddd; border-radius: 4px; min-width: 100px; }}
        .stat-value {{ font-size: 24px; font-weight: bold; color: #007bff; }}
        .passed {{ color: #28a745; }}
        .failed {{ color: #dc3545; }}
        button {{ background: #007bff; color: white; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; margin: 5px; }}
        button:hover {{ background: #0056b3; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🧪 Behavior Test Report</h1>

        <div class="summary">
            <h2>Test Run Summary</h2>
            <p><strong>Run ID:</strong> {metadata['test_run_id']}</p>
            <p><strong>Test Suite:</strong> {metadata['test_suite']}</p>
            <p><strong>Start Time:</strong> {metadata['start_time']}</p>
            <p><strong>Environment:</strong> OIDC Provider: {metadata['environment'].get('oidc_provider', 'unknown')}</p>
        </div>

        <div class="stats">
            <div class="stat">
                <div class="stat-value">{len(results)}</div>
                <div>Total Tests</div>
            </div>
            <div class="stat">
                <div class="stat-value passed">{sum(1 for v in validations if v.get('passed'))}</div>
                <div>Passed</div>
            </div>
            <div class="stat">
                <div class="stat-value failed">{sum(1 for v in validations if not v.get('passed'))}</div>
                <div>Failed</div>
            </div>
            <div class="stat">
                <div class="stat-value">{int(sum(1 for v in validations if v.get('passed')) / len(validations) * 100) if validations else 0}%</div>
                <div>Success Rate</div>
            </div>
        </div>

        <div>
            <button onclick="toggleAll(true)">Expand All</button>
            <button onclick="toggleAll(false)">Collapse All</button>
            <button onclick="showOnly('passed')">Show Passed Only</button>
            <button onclick="showOnly('failed')">Show Failed Only</button>
            <button onclick="showOnly('all')">Show All</button>
        </div>

        <h2>Test Results</h2>'''

# Add individual test results
for i, result in enumerate(results):
    validation = validations[i] if i < len(validations) else {'passed': False}
    test_id = result.get('test_id', f'test-{i}')
    test_name = result.get('name', 'Unnamed Test')
    test_desc = result.get('description', '')

    status_class = 'test-passed' if validation.get('passed') else 'test-failed'
    status_text = 'PASSED' if validation.get('passed') else 'FAILED'
    status_color = 'passed' if validation.get('passed') else 'failed'

    response_time = result.get('response', {}).get('response_time_ms', 0)

    html_content += f'''
        <div class="test-result {status_class}" data-status="{'passed' if validation.get('passed') else 'failed'}">
            <div class="test-header" onclick="toggleDetails('{test_id}')">
                <h3>{test_name} <span class="{status_color}">({status_text})</span></h3>
                <p>{test_desc}</p>
                <small>Test ID: {test_id} | Response Time: {response_time}ms</small>
            </div>
            <div class="test-details" id="details-{test_id}">
                <h4>Request</h4>
                <pre>{json.dumps(result.get('request', {}), indent=2)}</pre>

                <h4>Response</h4>
                <pre>{json.dumps(result.get('response', {}), indent=2)}</pre>

                <h4>Validation Results</h4>
                <pre>{json.dumps(validation, indent=2)}</pre>
            </div>
        </div>'''

html_content += '''
        </div>
    </div>

    <script>
        function toggleDetails(testId) {
            const details = document.getElementById('details-' + testId);
            details.classList.toggle('show');
        }

        function toggleAll(show) {
            const details = document.querySelectorAll('.test-details');
            details.forEach(detail => {
                if (show) {
                    detail.classList.add('show');
                } else {
                    detail.classList.remove('show');
                }
            });
        }

        function showOnly(filter) {
            const results = document.querySelectorAll('.test-result');
            results.forEach(result => {
                if (filter === 'all') {
                    result.style.display = 'block';
                } else {
                    const status = result.dataset.status;
                    result.style.display = (status === filter) ? 'block' : 'none';
                }
            });
        }
    </script>
</body>
</html>'''

# Write report file
report_file = f'{results_dir}/reports/behavior-test-report.html'
with open(report_file, 'w') as f:
    f.write(html_content)

print(f"Report generated: {report_file}")
EOF

    log_success "Test report generated: $report_file"
}

# Cleanup function
cleanup_tests() {
    if [[ "$CLEANUP_ON_EXIT" == "false" ]]; then
        return 0
    fi

    log_info "Cleaning up test data..."

    # Run cleanup requests from test definitions
    for test_file in "$PROJECT_ROOT/tests/expected-behavior"/*.json; do
        if [[ -f "$test_file" ]]; then
            python3 << EOF
import json
import requests

try:
    with open('$test_file', 'r') as f:
        test_suite = json.load(f)

    cleanup = test_suite.get('test_cleanup', {})
    cleanup_requests = cleanup.get('cleanup_requests', [])

    for cleanup_req in cleanup_requests:
        if cleanup_req.get('method') == 'DELETE':
            try:
                headers = cleanup_req.get('headers', {})
                headers = {k: v.replace('\${ADMIN_KEY}', '$ADMIN_KEY') for k, v in headers.items()}

                response = requests.delete(
                    cleanup_req['url'],
                    headers=headers,
                    timeout=10
                )

                ignore_errors = cleanup_req.get('ignore_errors', [])
                if response.status_code not in ignore_errors and not response.ok:
                    print(f"Cleanup warning: {response.status_code} for {cleanup_req['url']}")
            except Exception as e:
                print(f"Cleanup error (ignored): {e}")

except Exception as e:
    print(f"Cleanup processing error: {e}")
EOF
        fi
    done

    log_success "Cleanup completed"
}

# Main execution function
main() {
    parse_arguments "$@"

    log_info "Starting Behavior Testing Framework"
    log_info "Test Run ID: $TEST_RUN_ID"
    log_info "Test Suite: $TEST_SUITE"
    log_info "Results Directory: $RESULTS_DIR"

    # Validate environment
    if ! validate_environment; then
        exit 1
    fi

    # Setup results directory
    setup_results_directory

    # Trap for cleanup
    trap cleanup_tests EXIT

    local overall_success=true

    # Run test suites
    if [[ "$TEST_SUITE" == "all" ]]; then
        for suite in portal-backend-api oidc-flow consumer-management; do
            if ! run_test_suite "$suite"; then
                overall_success=false
                if [[ "$CONTINUE_ON_FAILURE" == "false" ]]; then
                    break
                fi
            fi
        done
    else
        if ! run_test_suite "$TEST_SUITE"; then
            overall_success=false
        fi
    fi

    # Generate report
    generate_report

    # Final summary
    log_info "Behavior testing completed"
    if [[ "$overall_success" == "true" ]]; then
        log_success "All test suites passed successfully"
        exit 0
    else
        log_error "One or more test suites failed"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"