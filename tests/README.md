# Behavior Testing Framework

This directory contains the comprehensive behavior testing framework for the APISIX Gateway Portal, designed to validate expected vs actual behavior with systematic tracking and reporting.

## Overview

The testing framework provides three levels of testing:

1. **Comprehensive Behavior Testing** - JSON-defined test suites with expected vs actual validation
2. **Component-Specific Testing** - Focused scripts for individual components
3. **Manual Validation Scripts** - Quick verification tools for development

## Directory Structure

```
tests/
├── README.md                          # This file
├── expected-behavior/                  # Test definitions (JSON)
│   ├── portal-backend-api.json        # Portal backend endpoint tests
│   ├── oidc-flow.json                 # OIDC integration tests
│   └── consumer-management.json       # APISIX Consumer API tests
├── results/                           # Test execution results
│   ├── {timestamp}-{run-id}/          # Individual test runs
│   │   ├── raw/                       # Raw test results (JSON)
│   │   ├── processed/                 # Processed summaries
│   │   ├── reports/                   # HTML/JSON reports
│   │   └── artifacts/                 # Supporting files
└── scripts/ -> ../scripts/testing/    # Test execution scripts
```

## Quick Start

### Prerequisites

1. **Environment Setup**:
```bash
# Load environment configuration
source scripts/core/environment.sh
setup_environment entraid  # or keycloak

# Required environment variables
export DEV_MODE=true
export DEV_ADMIN_PASSWORD=your-secure-password
```

2. **Services Running**:
```bash
# Start all services
./scripts/lifecycle/start.sh --provider entraid --debug
```

### Running Tests

#### 1. Quick Portal Backend Testing
```bash
# Test portal backend endpoints with immediate feedback
./scripts/testing/test-portal-backend.sh

# Verbose output with response details
./scripts/testing/test-portal-backend.sh -v

# Test with specific user ID
./scripts/testing/test-portal-backend.sh --user my-test-user
```

#### 2. OIDC Integration Testing
```bash
# Test OIDC flow and configuration
./scripts/testing/test-oidc-flow.sh

# Verbose output with request/response details
./scripts/testing/test-oidc-flow.sh -v

# Test specific provider
./scripts/testing/test-oidc-flow.sh --provider entraid
```

#### 3. Comprehensive Behavior Testing
```bash
# Run all test suites with full behavior validation
./scripts/testing/behavior-test.sh

# Run specific test suite
./scripts/testing/behavior-test.sh portal-backend-api

# Continue on failure with verbose output
./scripts/testing/behavior-test.sh -v --continue-on-failure
```

## Test Suites

### Portal Backend API Tests

**File**: `expected-behavior/portal-backend-api.json`

**Coverage**:
- Health check endpoint validation
- Authentication requirement enforcement
- Portal dashboard functionality
- API key generation (get-key operation)
- API key recycling (recycle-key operation)
- Development admin routes (when DEV_MODE enabled)

**Example Usage**:
```bash
# Run only portal backend tests
./scripts/testing/behavior-test.sh portal-backend-api

# Quick test without full behavior framework
./scripts/testing/test-portal-backend.sh -v
```

### OIDC Integration Tests

**File**: `expected-behavior/oidc-flow.json`

**Coverage**:
- APISIX gateway connectivity
- APISIX Admin API access
- OIDC discovery endpoint accessibility
- Portal route redirect behavior
- Route configuration validation
- Provider-specific tests (EntraID/Keycloak)

**Example Usage**:
```bash
# Run OIDC flow tests
./scripts/testing/behavior-test.sh oidc-flow

# Quick OIDC validation
./scripts/testing/test-oidc-flow.sh --provider entraid -v
```

### Consumer Management Tests

**File**: `expected-behavior/consumer-management.json`

**Coverage**:
- Consumer creation via Admin API
- Consumer retrieval and validation
- Key-auth plugin configuration
- Consumer plugin updates (key recycling)
- Consumer deletion
- Error scenario handling
- ETCD integration validation
- Performance benchmarks

**Example Usage**:
```bash
# Run consumer management tests
./scripts/testing/behavior-test.sh consumer-management
```

## Test Definition Format

Tests are defined in JSON format with the following structure:

```json
{
  "test_suite_name": "Portal Backend API Behavior Tests",
  "test_suite_version": "1.0.0",
  "description": "Validates expected behavior of portal backend API endpoints",
  "prerequisites": {
    "services_required": ["apisix-dev", "etcd-dev", "portal-backend-dev"],
    "environment_variables": ["ADMIN_KEY", "DEV_MODE"]
  },
  "tests": [
    {
      "test_id": "unique_test_identifier",
      "name": "Human-readable test name",
      "description": "Detailed test description",
      "request": {
        "method": "POST",
        "url": "http://localhost:3001/portal/get-key",
        "headers": {
          "X-User-Oid": "test-user",
          "Content-Type": "application/json"
        },
        "body": null,
        "timeout": 15
      },
      "expected_response": {
        "status_code": 200,
        "headers": {
          "content-type": "application/json"
        },
        "body": {
          "success": true,
          "message": "API key retrieved successfully"
        }
      },
      "validation_rules": [
        "response.status_code == 200",
        "response.json.success == True",
        "len(response.json.api_key) >= 32"
      ]
    }
  ],
  "test_cleanup": {
    "cleanup_requests": [...]
  }
}
```

## Behavior Validation

The framework validates actual behavior against expected outcomes using:

1. **Status Code Validation** - HTTP response codes
2. **Header Validation** - Response headers and content types
3. **Body Validation** - JSON structure and field values
4. **Content Validation** - Text contains/pattern matching
5. **Custom Validation Rules** - Python expressions for complex validation

### Validation Rules Examples

```python
# Status code validation
"response.status_code == 200"
"response.status_code in [200, 201]"

# JSON field validation
"response.json.success == True"
"len(response.json.api_key) >= 32"
"'portal' in response.json.message.lower()"

# Header validation
"'application/json' in response.headers['content-type']"

# Response time validation
"response.response_time_ms < 1000"
```

## Test Reports

### HTML Reports

Comprehensive HTML reports are generated automatically:

```bash
# Generate report (automatic after test run)
open tests/results/latest/reports/behavior-test-report.html
```

**Report Features**:
- Test run summary with statistics
- Individual test results with expand/collapse
- Request/response details for each test
- Validation results and failure analysis
- Filter options (passed/failed/all tests)
- Interactive JavaScript interface

### JSON Reports

Machine-readable results for CI/CD integration:

```bash
# Access JSON results
cat tests/results/latest/processed/portal-backend-api-summary.json
```

## Development Workflow

### 1. Adding New Tests

1. **Create Test Definition**:
```bash
# Copy existing test file as template
cp tests/expected-behavior/portal-backend-api.json tests/expected-behavior/my-new-tests.json

# Edit test definition
vim tests/expected-behavior/my-new-tests.json
```

2. **Run Tests**:
```bash
# Test new definition
./scripts/testing/behavior-test.sh my-new-tests -v
```

### 2. Debugging Test Failures

1. **Run with Verbose Output**:
```bash
./scripts/testing/behavior-test.sh portal-backend-api -v
```

2. **Examine Raw Results**:
```bash
cat tests/results/latest/raw/portal-backend-api-get_key_new_user.json
cat tests/results/latest/raw/portal-backend-api-get_key_new_user-validation.json
```

3. **Check Service Logs**:
```bash
docker logs portal-backend-dev
docker logs apisix-dev
```

### 3. Continuous Integration

```bash
# CI/CD pipeline integration
./scripts/testing/behavior-test.sh --continue-on-failure --results-dir ci-results
exit_code=$?

# Parse results for CI
python3 -c "
import json
with open('ci-results/processed/*-summary.json', 'r') as f:
    summary = json.load(f)
    print(f'Tests: {summary[\"total_tests\"]} Passed: {summary[\"passed_tests\"]}')
"
```

## Environment Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ADMIN_KEY` | APISIX Admin API key | `edd1c9f034335f13...` |
| `APISIX_ADMIN_API` | APISIX Admin API URL | `http://localhost:9180/apisix/admin` |
| `OIDC_DISCOVERY_ENDPOINT` | OIDC discovery URL | `https://login.microsoftonline.com/{tenant}/v2.0/.well-known/openid-configuration` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DEV_MODE` | Enable development mode | `false` |
| `DEV_ADMIN_PASSWORD` | Development admin password | (none) |
| `OIDC_PROVIDER_NAME` | Provider name for tests | `unknown` |

## Troubleshooting

### Common Issues

#### 1. Tests Fail Due to Missing Services

**Error**: `Required services not running: apisix-dev`

**Solution**:
```bash
./scripts/lifecycle/start.sh --provider entraid
```

#### 2. Environment Variables Not Set

**Error**: `Missing required environment variables: ADMIN_KEY`

**Solution**:
```bash
source scripts/core/environment.sh
setup_environment entraid
```

#### 3. OIDC Discovery Endpoint Unreachable

**Error**: `OIDC discovery endpoint is not accessible`

**Diagnosis**:
```bash
# Test from container network
docker exec apisix-dev curl -s "$OIDC_DISCOVERY_ENDPOINT"

# Check provider-specific configuration
./scripts/testing/test-oidc-flow.sh --provider entraid -v
```

#### 4. Portal Backend Not Responding

**Error**: `Portal backend is not accessible at http://localhost:3001`

**Diagnosis**:
```bash
# Check service status
docker ps | grep portal-backend

# Check service logs
docker logs portal-backend-dev

# Test direct connectivity
curl http://localhost:3001/health
```

### Debug Mode

Enable detailed debugging for all tests:

```bash
# Set debug environment
export DEBUG=true

# Run tests with maximum verbosity
./scripts/testing/behavior-test.sh -v --continue-on-failure all
```

## Performance Benchmarks

The framework includes performance validation:

- **Portal Response Time**: `< 2000ms`
- **OIDC Redirect Time**: `< 1000ms`
- **Consumer Creation**: `< 1000ms`
- **Consumer Retrieval**: `< 500ms`

Performance data is captured in test results and included in reports.

## Best Practices

### 1. Test Organization

- **Group Related Tests** - Keep related functionality in same test suite
- **Use Descriptive Names** - Clear test IDs and names for easy identification
- **Include Cleanup** - Always define cleanup operations for test data

### 2. Validation Rules

- **Be Specific** - Test specific values rather than just existence
- **Test Edge Cases** - Include both positive and negative test scenarios
- **Validate Security** - Test authentication and authorization requirements

### 3. Test Maintenance

- **Regular Execution** - Run tests after code changes
- **Update Expected Behavior** - Keep test definitions current with implementation
- **Monitor Performance** - Track test execution time trends

---

This behavior testing framework provides comprehensive validation of the APISIX Gateway Portal implementation, ensuring reliable operation and catching regressions early in the development process.