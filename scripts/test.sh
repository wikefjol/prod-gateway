#!/bin/bash
# APISIX Gateway - Test Environment Management
# Usage: ./scripts/test.sh [up|down|reset|status|logs|routes|bootstrap]

set -euo pipefail

# Configuration
PROJECT_NAME="apisix-test"
ENV_FILE=".env.test"
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.test.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment variables
set -a
source "$PROJECT_ROOT/$ENV_FILE"
set +a

# Change to project root
cd "$PROJECT_ROOT"

# Helper functions
log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_error() {
    echo "❌ $*" >&2
}

# Check if services are running
check_services() {
    docker compose --project-name "$PROJECT_NAME" $COMPOSE_FILES ps --services --filter "status=running" 2>/dev/null || true
}

# Wait for APISIX to be healthy
wait_for_apisix() {
    log_info "Waiting for APISIX to be healthy..."
    for i in {1..30}; do
        if curl -s -f http://localhost:9181/apisix/admin/routes -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; then
            log_success "APISIX is healthy"
            return 0
        fi
        sleep 2
    done
    log_error "APISIX failed to become healthy"
    return 1
}

case "${1:-help}" in
    up)
        log_info "Starting test environment..."
        docker compose --project-name "$PROJECT_NAME" $COMPOSE_FILES --env-file "$ENV_FILE" up -d
        log_success "Test environment started"
        log_info "Gateway: http://localhost:9081"
        log_info "Admin API: http://localhost:9181 (localhost only)"
        log_info "Portal: http://localhost:3002 (localhost only)"
        ;;

    down)
        log_info "Stopping test environment..."
        docker compose --project-name "$PROJECT_NAME" down
        if [ "${2:-}" == "--clean" ]; then
            log_info "Removing volumes and networks..."
            docker compose --project-name "$PROJECT_NAME" down -v --remove-orphans
        fi
        log_success "Test environment stopped"
        ;;

    reset)
        log_info "Resetting test environment..."
        $0 down ${2:---clean}
        $0 up
        if wait_for_apisix; then
            $0 bootstrap
        fi
        log_success "Test environment reset complete"
        ;;

    status)
        log_info "Test environment status:"
        running_services=$(check_services)
        if [ -n "$running_services" ]; then
            echo "Running services:"
            echo "$running_services" | sed 's/^/  /'
            echo
            log_info "Service health:"
            docker compose --project-name "$PROJECT_NAME" $COMPOSE_FILES ps
        else
            echo "No services running"
        fi
        ;;

    logs)
        service="${2:-}"
        follow_flag=""
        if [ "${3:-}" == "--follow" ] || [ "${3:-}" == "-f" ]; then
            follow_flag="-f"
        fi
        if [ -n "$service" ]; then
            docker compose --project-name "$PROJECT_NAME" logs $follow_flag "$service"
        else
            docker compose --project-name "$PROJECT_NAME" logs $follow_flag
        fi
        ;;

    routes)
        if ! curl -s -f http://localhost:9181/apisix/admin/routes -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; then
            log_error "APISIX admin API not accessible. Is the environment running?"
            exit 1
        fi
        log_info "Configured routes:"
        curl -s http://localhost:9181/apisix/admin/routes -H "X-API-KEY: $ADMIN_KEY" | jq -r '.list[] | "Route \(.value.id // "unknown"): \(.value.name // "unnamed") - \(.value.uri // .value.uris[0] // "no-uri")"' 2>/dev/null || \
        curl -s http://localhost:9181/apisix/admin/routes -H "X-API-KEY: $ADMIN_KEY"
        ;;

    bootstrap)
        if ! wait_for_apisix; then
            log_error "Cannot bootstrap: APISIX not healthy"
            exit 1
        fi
        log_info "Running bootstrap to load routes..."
        "$SCRIPT_DIR/bootstrap.sh" test
        ;;

    help|*)
        echo "APISIX Gateway - Test Environment"
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  up          Start test environment"
        echo "  down        Stop test environment"
        echo "              --clean  Remove volumes and networks"
        echo "  reset       Complete reset (down + up + bootstrap)"
        echo "              --clean  Remove volumes before reset"
        echo "  status      Show environment status"
        echo "  logs        Show logs for all services"
        echo "              [service] Show logs for specific service"
        echo "              --follow  Follow log output"
        echo "  routes      List configured APISIX routes"
        echo "  bootstrap   Load routes into APISIX"
        echo "  help        Show this help message"
        echo
        echo "Examples:"
        echo "  $0 reset --clean    # Complete reset with cleanup"
        echo "  $0 logs apisix -f   # Follow APISIX logs"
        echo "  $0 routes           # List all routes"
        ;;
esac