#!/bin/bash
# Universal APISIX Gateway Startup Script
# Supports multiple OIDC providers with clean separation of concerns

set -euo pipefail

# Configuration defaults
PROVIDER=${OIDC_PROVIDER_NAME:-"keycloak"}
ENVIRONMENT=${ENVIRONMENT:-"dev"}
DEBUG_MODE=${DEBUG_MODE:-false}
FORCE_RECREATE=${FORCE_RECREATE:-false}

# Script setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load core environment functions
# shellcheck source=../core/environment.sh
source "$SCRIPT_DIR/../core/environment.sh"

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Universal APISIX Gateway startup script with provider switching support.

OPTIONS:
    -p, --provider PROVIDER     OIDC provider to use (keycloak, entraid)
    -e, --environment ENV       Environment to use (dev, test, prod)
    -d, --debug                 Enable debug mode with diagnostic containers
    -f, --force-recreate        Force recreation of containers
    -h, --help                  Show this help message

ENVIRONMENT VARIABLES:
    OIDC_PROVIDER_NAME          Override provider (default: keycloak)
    ENVIRONMENT                 Override environment (default: dev)
    DEBUG_MODE                  Enable debug mode (default: false)
    FORCE_RECREATE             Force container recreation (default: false)

EXAMPLES:
    # Start with Keycloak (default)
    $0

    # Start with EntraID
    $0 --provider entraid

    # Start with debug mode
    $0 --provider entraid --debug

    # Force recreation of containers
    $0 --provider keycloak --force-recreate

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--provider)
                PROVIDER="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -d|--debug)
                DEBUG_MODE=true
                shift
                ;;
            -f|--force-recreate)
                FORCE_RECREATE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required but not installed"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose is required but not available"
        exit 1
    fi

    # Check project structure
    local required_dirs=("config" "infrastructure/docker" "scripts/core")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$PROJECT_ROOT/$dir" ]]; then
            log_error "Missing required directory: $dir"
            exit 1
        fi
    done

    log_success "Pre-flight checks completed"
}

# Stop any existing containers
stop_existing() {
    log_info "Stopping any existing containers..."

    # Try to stop with current configuration
    if docker compose -f "$PROJECT_ROOT/infrastructure/docker/base.yml" \
                      -f "$PROJECT_ROOT/infrastructure/docker/providers.yml" \
                      -f "$PROJECT_ROOT/infrastructure/docker/debug.yml" \
                      ps -q >/dev/null 2>&1; then
        docker compose -f "$PROJECT_ROOT/infrastructure/docker/base.yml" \
                      -f "$PROJECT_ROOT/infrastructure/docker/providers.yml" \
                      -f "$PROJECT_ROOT/infrastructure/docker/debug.yml" \
                      down
    fi

    # Clean up any orphaned containers
    docker container prune -f >/dev/null 2>&1 || true

    log_success "Existing containers stopped"
}

# Start services
start_services() {
    log_info "Starting APISIX Gateway infrastructure..."

    # Generate docker-compose command
    generate_compose_command "$PROVIDER" "$ENVIRONMENT" "$DEBUG_MODE"

    # Build compose command array
    local compose_cmd=(
        docker compose
        -f "$PROJECT_ROOT/infrastructure/docker/base.yml"
        -f "$PROJECT_ROOT/infrastructure/docker/providers.yml"
    )

    # Add debug compose file if debug mode is enabled
    if [[ "$DEBUG_MODE" == "true" ]]; then
        compose_cmd+=(-f "$PROJECT_ROOT/infrastructure/docker/debug.yml")
    fi

    # Add profile selection
    compose_cmd+=(--profile "$PROVIDER")
    if [[ "$DEBUG_MODE" == "true" ]]; then
        compose_cmd+=(--profile debug)
    fi

    # Add force recreate if requested
    local up_args=(up -d)
    if [[ "$FORCE_RECREATE" == "true" ]]; then
        up_args+=(--force-recreate)
    fi

    # Execute compose command
    log_info "Executing: ${compose_cmd[*]} ${up_args[*]} etcd-dev apisix-dev loader-dev portal-backend"
    "${compose_cmd[@]}" "${up_args[@]}" etcd-dev apisix-dev loader-dev portal-backend

    log_success "Services started successfully"
}

# Wait for services to be healthy
wait_for_services() {
    log_info "Waiting for services to be healthy..."

    # Wait for APISIX
    log_info "Waiting for APISIX Gateway..."
    local max_attempts=60
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -fsS "http://localhost:${APISIX_ADMIN_PORT:-9180}/apisix/admin/routes" \
                -H "X-API-KEY: ${ADMIN_KEY}" >/dev/null 2>&1; then
            log_success "APISIX Gateway is ready"
            break
        fi

        if [[ $attempt -eq $max_attempts ]]; then
            log_error "APISIX Gateway failed to start after $max_attempts attempts"
            return 1
        fi

        echo -n "."
        sleep 2
        ((attempt++))
    done

    # Wait for provider-specific services
    case "$PROVIDER" in
        "keycloak")
            wait_for_keycloak
            ;;
        "entraid")
            # EntraID is external, just validate configuration
            validate_entraid_accessibility
            ;;
    esac

    log_success "All services are healthy"
}

# Wait for Keycloak to be ready
wait_for_keycloak() {
    log_info "Waiting for Keycloak..."
    local max_attempts=60
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -fsS "http://localhost:8080/health/ready" >/dev/null 2>&1; then
            log_success "Keycloak is ready"
            return 0
        fi

        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Keycloak failed to start after $max_attempts attempts"
            return 1
        fi

        echo -n "."
        sleep 3
        ((attempt++))
    done
}

# Validate EntraID accessibility
validate_entraid_accessibility() {
    log_info "Validating EntraID configuration..."

    if [[ "$OIDC_DISCOVERY_ENDPOINT" =~ placeholder ]]; then
        log_warning "EntraID discovery endpoint contains placeholder values"
        log_warning "Please update secrets/entraid-dev.env with actual credentials"
        return 0
    fi

    # Test discovery endpoint accessibility
    if curl -fsS "$OIDC_DISCOVERY_ENDPOINT" >/dev/null 2>&1; then
        log_success "EntraID discovery endpoint is accessible"
    else
        log_warning "EntraID discovery endpoint is not accessible"
        log_warning "This may be normal if using placeholder values"
    fi
}

# Show status and next steps
show_status() {
    echo ""
    echo "🎉 APISIX Gateway Started Successfully!"
    echo "======================================"
    echo ""
    echo "Configuration Summary:"
    echo "  Provider: $PROVIDER"
    echo "  Environment: $ENVIRONMENT"
    echo "  Debug Mode: $DEBUG_MODE"
    echo ""
    echo "Services:"
    echo "  🌐 APISIX Gateway:    http://localhost:${APISIX_NODE_LISTEN:-9080}"
    echo "  🔧 APISIX Admin:      http://localhost:${APISIX_ADMIN_PORT:-9180}"
    echo "  📊 APISIX Dashboard:  Built-in at Admin API"

    if [[ "$PROVIDER" == "keycloak" ]]; then
        echo "  🔑 Keycloak:          http://localhost:8080"
        echo "     Admin: admin/admin"
    fi

    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo ""
        echo "Debug Tools:"
        echo "  🐛 Debug Toolkit:     docker exec -it apisix-debug-toolkit bash"
        echo "  🌐 HTTP Client:       docker exec -it apisix-http-client sh"
        echo "  📋 Config Inspector:  docker exec -it apisix-config-inspector sh"
    fi

    echo ""
    echo "Next Steps:"
    echo "  1. Test OIDC flow:      http://localhost:${APISIX_NODE_LISTEN:-9080}/portal"
    echo '  2. View routes:         curl -H "X-API-KEY: $ADMIN_KEY"' "http://localhost:${APISIX_ADMIN_PORT:-9180}/apisix/admin/routes"
    echo "  3. Check logs:          docker compose -f infrastructure/docker/base.yml logs -f"
    echo "  4. Stop environment:    ./scripts/lifecycle/stop.sh"

    if [[ "$PROVIDER" == "entraid" && "$OIDC_CLIENT_ID" =~ placeholder ]]; then
        echo ""
        echo "⚠️  EntraID Configuration Required:"
        echo "  1. Update secrets/entraid-dev.env with actual credentials"
        echo "  2. Restart services: $0 --provider entraid --force-recreate"
    fi

    echo ""
    echo "✅ Environment is ready for use!"
}

# Main execution
main() {
    echo "🚀 APISIX Gateway Universal Startup"
    echo "=================================="

    # Parse arguments
    parse_args "$@"

    # Load and validate environment
    setup_environment "$PROVIDER" "$ENVIRONMENT"

    # Run startup sequence
    preflight_checks
    stop_existing
    start_services
    wait_for_services
    show_status

    log_success "Startup completed successfully!"
}

# Handle interrupts gracefully
trap 'log_error "Startup interrupted"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"