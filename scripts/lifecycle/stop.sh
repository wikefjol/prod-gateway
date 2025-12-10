#!/bin/bash
# Universal APISIX Gateway Stop Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load core environment functions
# shellcheck source=../core/environment.sh
source "$SCRIPT_DIR/../core/environment.sh"

# Load environment configuration if available
setup_environment "${OIDC_PROVIDER_NAME:-keycloak}" "${ENVIRONMENT:-dev}" 2>/dev/null || true

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Stop APISIX Gateway infrastructure.

OPTIONS:
    --clean         Remove volumes and networks
    -h, --help      Show this help message

EOF
}

# Parse arguments
CLEAN_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_MODE=true
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

# Main stop function
main() {
    log_info "Stopping APISIX Gateway infrastructure..."

    # Stop all services
    docker compose \
        -f "$PROJECT_ROOT/infrastructure/docker/base.yml" \
        -f "$PROJECT_ROOT/infrastructure/docker/providers.yml" \
        -f "$PROJECT_ROOT/infrastructure/docker/debug.yml" \
        down

    if [[ "$CLEAN_MODE" == "true" ]]; then
        log_info "Cleaning up volumes and networks..."
        docker compose \
            -f "$PROJECT_ROOT/infrastructure/docker/base.yml" \
            -f "$PROJECT_ROOT/infrastructure/docker/providers.yml" \
            -f "$PROJECT_ROOT/infrastructure/docker/debug.yml" \
            down --volumes --remove-orphans
    fi

    log_success "APISIX Gateway stopped successfully"
}

main