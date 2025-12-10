#!/bin/bash
# Configuration Inspector
# Displays current configuration and validates setup

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment functions if available
if [[ -f "$PROJECT_ROOT/scripts/core/environment.sh" ]]; then
    # shellcheck source=../core/environment.sh
    source "$PROJECT_ROOT/scripts/core/environment.sh"

    # Try to load current environment if provider is set
    if [[ -n "${OIDC_PROVIDER_NAME:-}" ]]; then
        log_info "Loading existing environment: ${OIDC_PROVIDER_NAME}"
        setup_environment "${OIDC_PROVIDER_NAME}" "${ENVIRONMENT:-dev}" 2>/dev/null || true
    fi
else
    # Fallback logging functions
    log_info() { echo "ℹ️  $*"; }
    log_success() { echo "✅ $*"; }
    log_warning() { echo "⚠️  $*"; }
    log_error() { echo "❌ $*" >&2; }
fi

log_header() { echo ""; echo "=== $* ==="; }

# Display environment information
show_environment() {
    log_header "Environment Information"
    echo "Provider: ${OIDC_PROVIDER_NAME:-not set}"
    echo "Environment: ${ENVIRONMENT:-not set}"
    echo "Debug Mode: ${DEBUG:-false}"
    echo ""
}

# Display OIDC configuration
show_oidc_config() {
    log_header "OIDC Configuration"
    echo "Client ID: ${OIDC_CLIENT_ID:-not set}"
    echo "Discovery: ${OIDC_DISCOVERY_ENDPOINT:-not set}"
    echo "Redirect URI: ${OIDC_REDIRECT_URI:-not set}"
    echo "Session Secret: ${OIDC_SESSION_SECRET:+*****}${OIDC_SESSION_SECRET:-not set}"
    echo "Scope: ${OIDC_SCOPE:-not set}"
    echo ""

    # Check for placeholder values
    if [[ "${OIDC_CLIENT_ID:-}" == *"placeholder"* ]]; then
        log_warning "Client ID contains placeholder value"
    fi

    if [[ "${OIDC_DISCOVERY_ENDPOINT:-}" == *"placeholder"* ]]; then
        log_warning "Discovery endpoint contains placeholder value"
    fi
}

# Display APISIX configuration
show_apisix_config() {
    log_header "APISIX Configuration"
    echo "Admin API: ${APISIX_ADMIN_API:-not set}"
    echo "Data Plane: ${DATA_PLANE:-not set}"
    echo "Node Listen: ${APISIX_NODE_LISTEN:-not set}"
    echo "Admin Port: ${APISIX_ADMIN_PORT:-not set}"
    echo "Admin Key: ${ADMIN_KEY:+*****}${ADMIN_KEY:-not set}"
    echo "Viewer Key: ${VIEWER_KEY:+*****}${VIEWER_KEY:-not set}"
    echo ""
}

# Display file structure
show_file_structure() {
    log_header "Configuration File Structure"

    # Check for critical files
    local files=(
        "config/shared/base.env"
        "config/shared/apisix.env"
        "config/providers/${OIDC_PROVIDER_NAME:-unknown}/dev.env"
        "secrets/${OIDC_PROVIDER_NAME:-unknown}-dev.env"
    )

    for file in "${files[@]}"; do
        local full_path="$PROJECT_ROOT/$file"
        if [[ -f "$full_path" ]]; then
            local size
            size=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo "unknown")
            echo "✓ $file ($size bytes)"
        else
            echo "✗ $file (missing)"
        fi
    done
    echo ""
}

# Display Docker configuration
show_docker_config() {
    log_header "Docker Configuration"

    # Check compose files
    local compose_files=(
        "infrastructure/docker/base.yml"
        "infrastructure/docker/providers.yml"
        "infrastructure/docker/debug.yml"
    )

    for file in "${compose_files[@]}"; do
        local full_path="$PROJECT_ROOT/$file"
        if [[ -f "$full_path" ]]; then
            echo "✓ $file"
        else
            echo "✗ $file (missing)"
        fi
    done
    echo ""

    # Check running containers
    echo "Running Containers:"
    if command -v docker >/dev/null 2>&1; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "label=com.docker.compose.project" 2>/dev/null || echo "No containers running"
    else
        echo "Docker not available"
    fi
    echo ""
}

# Display provider-specific information
show_provider_info() {
    log_header "Provider-Specific Information"

    case "${OIDC_PROVIDER_NAME:-}" in
        "keycloak")
            show_keycloak_info
            ;;
        "entraid")
            show_entraid_info
            ;;
        *)
            echo "Unknown or unset provider: ${OIDC_PROVIDER_NAME:-not set}"
            ;;
    esac
    echo ""
}

show_keycloak_info() {
    echo "Provider: Keycloak"
    echo "Admin URL: ${KEYCLOAK_ADMIN_URL:-not set}"
    echo "Realm: ${KEYCLOAK_REALM:-not set}"
    echo "Client Secret: ${KEYCLOAK_CLIENT_SECRET:+*****}${KEYCLOAK_CLIENT_SECRET:-not set}"

    # Test Keycloak connectivity if available
    if command -v curl >/dev/null 2>&1 && [[ -n "${KEYCLOAK_ADMIN_URL:-}" ]]; then
        if curl -fs "${KEYCLOAK_ADMIN_URL}/health/ready" >/dev/null 2>&1; then
            log_success "Keycloak is accessible"
        else
            log_warning "Keycloak is not accessible"
        fi
    fi
}

show_entraid_info() {
    echo "Provider: Microsoft EntraID (Azure AD)"
    echo "Tenant ID: ${ENTRAID_TENANT_ID:-not set}"
    echo "Authority: ${ENTRAID_AUTHORITY:-not set}"
    echo "Client Secret: ${ENTRAID_CLIENT_SECRET:+*****}${ENTRAID_CLIENT_SECRET:-not set}"

    # Extract tenant from discovery URL
    if [[ "${OIDC_DISCOVERY_ENDPOINT:-}" =~ /([^/]+)/v2\.0/ ]]; then
        local tenant_from_url="${BASH_REMATCH[1]}"
        echo "Tenant (from URL): $tenant_from_url"

        if [[ "$tenant_from_url" == "placeholder-tenant-id-for-testing" ]]; then
            log_warning "Tenant ID is placeholder - update with actual tenant"
        fi
    fi
}

# Validate configuration
validate_config() {
    log_header "Configuration Validation"

    local issues=0

    # Required variables
    local required_vars=(
        "OIDC_PROVIDER_NAME"
        "OIDC_CLIENT_ID"
        "OIDC_CLIENT_SECRET"
        "OIDC_DISCOVERY_ENDPOINT"
        "OIDC_REDIRECT_URI"
        "ADMIN_KEY"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Missing required variable: $var"
            ((issues++))
        fi
    done

    # Check for placeholder values
    local placeholder_vars=(
        "OIDC_CLIENT_ID:placeholder-client-id"
        "OIDC_CLIENT_SECRET:placeholder-client-secret"
        "OIDC_DISCOVERY_ENDPOINT:placeholder-tenant-id"
    )

    for check in "${placeholder_vars[@]}"; do
        local var="${check%:*}"
        local placeholder="${check#*:}"

        if [[ "${!var:-}" == *"$placeholder"* ]]; then
            log_warning "Variable $var contains placeholder value"
            ((issues++))
        fi
    done

    # Summary
    if [[ $issues -eq 0 ]]; then
        log_success "Configuration validation passed"
    else
        log_warning "$issues configuration issue(s) found"
    fi

    echo ""
}

# Display network information
show_network_info() {
    log_header "Network Information"

    if command -v ip >/dev/null 2>&1; then
        echo "Network Interfaces:"
        ip -4 addr show | grep -E '^[0-9]+:|inet ' | sed 's/^/  /'
        echo ""
    fi

    echo "DNS Resolution:"
    local hosts=("apisix-dev" "etcd-dev")

    case "${OIDC_PROVIDER_NAME:-}" in
        "keycloak")
            hosts+=("keycloak-dev")
            ;;
    esac

    for host in "${hosts[@]}"; do
        if command -v nslookup >/dev/null 2>&1; then
            if nslookup "$host" >/dev/null 2>&1; then
                echo "  ✓ $host"
            else
                echo "  ✗ $host"
            fi
        elif command -v getent >/dev/null 2>&1; then
            if getent hosts "$host" >/dev/null 2>&1; then
                echo "  ✓ $host"
            else
                echo "  ✗ $host"
            fi
        else
            echo "  ? $host (no DNS tools available)"
        fi
    done
    echo ""
}

# Show secrets information (without revealing actual secrets)
show_secrets_info() {
    log_header "Secrets Information"

    local secrets_file="$PROJECT_ROOT/secrets/${OIDC_PROVIDER_NAME:-unknown}-${ENVIRONMENT:-dev}.env"

    if [[ -f "$secrets_file" ]]; then
        echo "Secrets file: $(basename "$secrets_file")"
        echo "Location: $secrets_file"
        echo "Size: $(stat -f%z "$secrets_file" 2>/dev/null || stat -c%s "$secrets_file" 2>/dev/null || echo "unknown") bytes"
        echo "Modified: $(stat -f%Sm "$secrets_file" 2>/dev/null || stat -c%y "$secrets_file" 2>/dev/null || echo "unknown")"

        # Count non-empty, non-comment lines
        local line_count
        line_count=$(grep -c '^[^#].*=' "$secrets_file" 2>/dev/null || echo "0")
        echo "Variables: $line_count"
    else
        log_warning "Secrets file not found: $secrets_file"
    fi
    echo ""
}

# Full inspection
run_full_inspection() {
    echo "🔍 APISIX Configuration Inspector"
    echo "================================"

    show_environment
    show_oidc_config
    show_apisix_config
    show_provider_info
    show_file_structure
    show_docker_config
    show_network_info
    show_secrets_info
    validate_config

    echo "🔍 Inspection completed"
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [SECTION]

Inspect APISIX Gateway configuration.

SECTIONS:
    env         Environment information
    oidc        OIDC configuration
    apisix      APISIX configuration
    provider    Provider-specific information
    files       Configuration file structure
    docker      Docker configuration
    network     Network information
    secrets     Secrets information
    validate    Configuration validation
    all         Full inspection (default)

EXAMPLES:
    $0          # Full inspection
    $0 oidc     # OIDC configuration only
    $0 validate # Validation only

EOF
}

# Main execution
main() {
    local section="${1:-all}"

    case "$section" in
        "env")
            show_environment
            ;;
        "oidc")
            show_oidc_config
            ;;
        "apisix")
            show_apisix_config
            ;;
        "provider")
            show_provider_info
            ;;
        "files")
            show_file_structure
            ;;
        "docker")
            show_docker_config
            ;;
        "network")
            show_network_info
            ;;
        "secrets")
            show_secrets_info
            ;;
        "validate")
            validate_config
            ;;
        "all")
            run_full_inspection
            ;;
        "-h"|"--help")
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown section: $section"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"