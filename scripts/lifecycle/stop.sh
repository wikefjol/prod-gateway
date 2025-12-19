#!/bin/bash
# Universal APISIX Gateway Stop Script
# Supports multiple OIDC providers with environment-specific project targeting

set -euo pipefail

# Configuration defaults
PROVIDER=${OIDC_PROVIDER_NAME:-"entraid"}
ENVIRONMENT=${ENVIRONMENT:-"dev"}
PROJECT=${COMPOSE_PROJECT_NAME:-"apisix-${ENVIRONMENT}"}
CLEAN_MODE=${CLEAN_MODE:-false}
STOP_ALL=${STOP_ALL:-false}

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

Universal APISIX Gateway stop script with environment-specific targeting.

OPTIONS:
    -p, --provider PROVIDER     OIDC provider (keycloak, entraid)
    -e, --environment ENV       Environment to stop (dev, test, prod)
    --project PROJECT           Docker Compose project name (default: apisix-{environment})
    --clean                     Remove volumes and networks
    --all                       Stop all APISIX environments (dev, test)
    -h, --help                  Show this help message

ENVIRONMENT VARIABLES:
    OIDC_PROVIDER_NAME          Override provider (default: entraid)
    ENVIRONMENT                 Override environment (default: dev)
    COMPOSE_PROJECT_NAME        Override project name
    CLEAN_MODE                  Remove volumes (default: false)
    STOP_ALL                    Stop all environments (default: false)

EXAMPLES:
    # Stop dev environment (default)
    $0

    # Stop test environment with EntraID
    $0 --provider entraid --environment test

    # Stop dev environment and clean volumes
    $0 --environment dev --clean

    # Stop all environments
    $0 --all

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
            --clean)
                CLEAN_MODE=true
                shift
                ;;
            --all)
                STOP_ALL=true
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

# Stop specific project
stop_project() {
    local project_name="$1"

    log_info "Stopping project: $project_name"

    # Build compose command array with project support
    local compose_cmd=(
        docker compose
        -p "$project_name"
        -f "$PROJECT_ROOT/infrastructure/docker/base.yml"
        -f "$PROJECT_ROOT/infrastructure/docker/providers.yml"
        -f "$PROJECT_ROOT/infrastructure/docker/debug.yml"
    )

    # Build down arguments
    local down_args=(down)
    if [[ "$CLEAN_MODE" == "true" ]]; then
        down_args+=(--volumes --remove-orphans)
    fi

    # Check if project has running containers
    if "${compose_cmd[@]}" ps -q >/dev/null 2>&1; then
        log_info "Executing: ${compose_cmd[*]} ${down_args[*]}"
        "${compose_cmd[@]}" "${down_args[@]}"
        log_success "Project $project_name stopped successfully"
    else
        log_info "No running containers found for project: $project_name"
    fi
}

# Stop all known environments
stop_all_environments() {
    log_info "Stopping all APISIX environments..."

    local environments=("dev" "test")
    local stopped_count=0

    for env in "${environments[@]}"; do
        local project="apisix-$env"
        if docker ps --filter "name=$project-" --quiet | grep -q .; then
            stop_project "$project"
            ((stopped_count++))
        else
            log_info "No running containers found for environment: $env"
        fi
    done

    if [[ $stopped_count -gt 0 ]]; then
        log_success "Stopped $stopped_count environment(s) successfully"
    else
        log_info "No APISIX environments were running"
    fi
}

# Main execution
main() {
    echo "🛑 APISIX Gateway Universal Stop"
    echo "==============================="

    # Parse arguments
    parse_args "$@"

    if [[ "$STOP_ALL" == "true" ]]; then
        stop_all_environments
    else
        # Load environment configuration for logging
        setup_environment "$PROVIDER" "$ENVIRONMENT" 2>/dev/null || true

        log_info "Configuration Summary:"
        log_info "  Provider: $PROVIDER"
        log_info "  Environment: $ENVIRONMENT"
        log_info "  Project: $PROJECT"
        log_info "  Clean Mode: $CLEAN_MODE"

        stop_project "$PROJECT"
    fi

    # Clean up orphaned containers if requested
    if [[ "$CLEAN_MODE" == "true" ]]; then
        log_info "Performing additional cleanup..."
        docker container prune -f >/dev/null 2>&1 || true
        docker network prune -f >/dev/null 2>&1 || true
        log_success "Additional cleanup completed"
    fi

    log_success "Stop operation completed successfully!"
}

# Execute main function with all arguments
main "$@"