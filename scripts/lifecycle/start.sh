#!/bin/bash
# Universal APISIX Gateway Startup Script
# Supports multiple OIDC providers with clean separation of concerns

set -euo pipefail

# Configuration defaults
PROVIDER=${OIDC_PROVIDER_NAME:-"entraid"}
ENVIRONMENT=${ENVIRONMENT:-"dev"}
PROJECT=${COMPOSE_PROJECT_NAME:-"apisix-${ENVIRONMENT}"}
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
    --project PROJECT           Docker Compose project name (default: apisix-{environment})
    -d, --debug                 Enable debug mode with diagnostic containers
    -f, --force-recreate        Force recreation of containers
    -h, --help                  Show this help message

ENVIRONMENT VARIABLES:
    OIDC_PROVIDER_NAME          Override provider (default: entraid)
    ENVIRONMENT                 Override environment (default: dev)
    COMPOSE_PROJECT_NAME        Override project name
    DEBUG_MODE                  Enable debug mode (default: false)
    FORCE_RECREATE             Force container recreation (default: false)

EXAMPLES:
    # Start with EntraID (default)
    $0

    # Start with Keycloak (if needed)
    $0 --provider keycloak

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
                # Update project name if not explicitly set
                if [[ "$PROJECT" == "apisix-"* ]]; then
                    PROJECT="apisix-${ENVIRONMENT}"
                fi
                shift 2
                ;;
            --project)
                PROJECT="$2"
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
    log_info "Stopping any existing containers for project: $PROJECT"

    # Try to stop with current project configuration
    local compose_cmd=(
        docker compose
        -p "$PROJECT"
        -f "$PROJECT_ROOT/infrastructure/docker/base.yml"
        -f "$PROJECT_ROOT/infrastructure/docker/providers.yml"
        -f "$PROJECT_ROOT/infrastructure/docker/debug.yml"
    )

    if "${compose_cmd[@]}" ps -q >/dev/null 2>&1; then
        "${compose_cmd[@]}" down
    fi

    # Clean up any orphaned containers
    docker container prune -f >/dev/null 2>&1 || true

    log_success "Existing containers stopped for project: $PROJECT"
}

# Validate required environment variables to prevent Docker Compose warnings
validate_compose_env_vars() {
    local required_vars=(
        "ADMIN_KEY"
        "VIEWER_KEY"
        "ETCD_HOST"
        "ENVIRONMENT"
        "APISIX_HOST_GATEWAY_PORT"
        "APISIX_HOST_ADMIN_PORT"
        "OIDC_CLIENT_ID"
        "OIDC_CLIENT_SECRET"
        "OIDC_DISCOVERY_ENDPOINT"
        "OIDC_REDIRECT_URI"
        "OIDC_SESSION_SECRET"
        "OIDC_PROVIDER_NAME"
    )

    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "FAIL FAST: Required environment variables are missing:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        log_error ""
        log_error "This will cause Docker Compose to show warnings about defaulting to blank strings."
        log_error "Environment setup failed - check your configuration files and secrets."
        return 1
    fi

    log_info "✅ All required environment variables are set"
}

# Start services
start_services() {
    log_info "Starting APISIX Gateway infrastructure..."

    # Generate docker-compose command
    generate_compose_command "$PROVIDER" "$ENVIRONMENT" "$DEBUG_MODE" "$PROJECT"

    # Build compose command array with project support
    local compose_cmd=(
        docker compose
        -p "$PROJECT"
        --env-file "$COMPOSE_ENV_FILE"
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

    # Fail-fast validation: ensure required vars are set to prevent Docker Compose warnings
    validate_compose_env_vars

    # Execute compose command (updated service names without -dev suffix)
    log_info "Executing: ${compose_cmd[*]} ${up_args[*]} etcd apisix loader portal-backend"
    "${compose_cmd[@]}" "${up_args[@]}" etcd apisix loader portal-backend

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
    echo "  Project: $PROJECT"
    echo "  Debug Mode: $DEBUG_MODE"
    echo ""
    # Load port information from complete env file
    if [[ -f "$COMPOSE_ENV_FILE" ]]; then
        source "$COMPOSE_ENV_FILE"
    fi

    echo "Services:"
    echo "  🌐 APISIX Gateway:    http://localhost:${APISIX_HOST_GATEWAY_PORT:-9080}"
    echo "  🔧 APISIX Admin:      http://localhost:${APISIX_HOST_ADMIN_PORT:-9180}"
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
    echo "  1. Test OIDC flow:      http://localhost:${APISIX_HOST_GATEWAY_PORT:-9080}/portal"
    echo '  2. View routes:         curl -H "X-API-KEY: $ADMIN_KEY"' "http://localhost:${APISIX_HOST_ADMIN_PORT:-9180}/apisix/admin/routes"
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