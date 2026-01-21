#!/bin/bash
# APISIX Gateway - Development Environment Management
# Usage: ./scripts/dev.sh [up|down|reset|status|logs|routes|bootstrap|build]

set -euo pipefail

# Configuration
PROJECT_NAME="apisix-dev"
ENV_FILE=".env.dev"
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.dev.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

set -a
source "$PROJECT_ROOT/$ENV_FILE"
set +a

ADMIN_API="${APISIX_ADMIN_API:-http://127.0.0.1:9180/apisix/admin}"

# Common flags for clean, reproducible container lifecycle
# --pull always      : Always pull latest base images
# --force-recreate   : Recreate containers even if config/image unchanged
# --remove-orphans   : Remove containers for services not defined in compose
UP_FLAGS="--pull always --force-recreate --remove-orphans -d"

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

log_warning() {
    echo "⚠️  $*"
}

# Confirm destructive operation
confirm_destructive_operation() {
    local operation="$1"
    echo
    log_warning "DESTRUCTIVE OPERATION: $operation"
    log_warning "This will DELETE ALL DATA including:"
    echo "    - All consumers and their API keys"
    echo "    - All custom configurations"
    echo "    - All etcd stored data"
    echo
    echo "To confirm this operation, type DELETE (all caps):"
    read -r confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log_error "Operation cancelled"
        exit 1
    fi
    log_info "Proceeding with destructive operation..."
}

# Check if services are running
check_services() {
    docker compose --project-name "$PROJECT_NAME" $COMPOSE_FILES ps --services --filter "status=running" 2>/dev/null || true
}

# Wait for APISIX to be healthy
wait_for_apisix() {
    log_info "Waiting for APISIX to be healthy..."
    for i in {1..30}; do
        if curl -s -f "$ADMIN_API/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; then
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
        log_info "Starting development environment (clean start)..."
        docker compose --project-name "$PROJECT_NAME" $COMPOSE_FILES --env-file "$ENV_FILE" up $UP_FLAGS
        log_success "Development environment started"
        log_info "Gateway: http://127.0.0.1:9080"
        log_info "Admin API: http://127.0.0.1:9180 (localhost only)"
        log_info "Portal: http://127.0.0.1:3001 (localhost only)"
        ;;

    down)
        log_info "Stopping development environment..."
        if [ "${2:-}" == "--clean" ]; then
            confirm_destructive_operation "down --clean"
            docker compose --project-name "$PROJECT_NAME" $COMPOSE_FILES --env-file "$ENV_FILE" down -v --remove-orphans
            log_success "Development environment stopped and all data removed"
        else
            docker compose --project-name "$PROJECT_NAME" $COMPOSE_FILES --env-file "$ENV_FILE" down --remove-orphans
            log_success "Development environment stopped (data preserved)"
        fi
        ;;

    reset)
        if [ "${2:-}" == "--clean" ]; then
            log_info "Resetting development environment with data cleanup..."
            confirm_destructive_operation "reset --clean"
            $0 down --clean
        else
            log_info "Resetting development environment (preserving data)..."
            $0 down
        fi
        $0 up
        if wait_for_apisix; then
            $0 bootstrap
        fi
        log_success "Development environment reset complete"
        ;;

    build)
        log_info "Building APISIX container..."
        if [ "${2:-}" == "--cache" ]; then
            log_info "Building with cache (faster, use for minor changes)..."
            docker compose --project-name "$PROJECT_NAME" $COMPOSE_FILES --env-file "$ENV_FILE" build --pull apisix
        else
            log_info "Building without cache (clean build, ensures latest)..."
            docker compose --project-name "$PROJECT_NAME" $COMPOSE_FILES --env-file "$ENV_FILE" build --no-cache --pull apisix
        fi
        log_success "APISIX container built successfully"
        log_info "Run '$0 up' to start with the new image"
        ;;

    status)
        log_info "Development environment status:"
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
        if ! curl -s -f "$ADMIN_API/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; then
            log_error "APISIX admin API not accessible. Is the environment running?"
            exit 1
        fi
        log_info "Configured routes:"
        curl -s "$ADMIN_API/routes" -H "X-API-KEY: $ADMIN_KEY" | jq -r '.list[] | "Route \(.value.id // "unknown"): \(.value.name // "unnamed") - \(.value.uri // .value.uris[0] // "no-uri")"' 2>/dev/null || \
        curl -s "$ADMIN_API/routes" -H "X-API-KEY: $ADMIN_KEY"
        ;;

    bootstrap)
        if ! wait_for_apisix; then
            log_error "Cannot bootstrap: APISIX not healthy"
            exit 1
        fi
        log_info "Running bootstrap to load routes..."
        "$SCRIPT_DIR/bootstrap.sh" dev
        ;;

    help|*)
        echo "APISIX Gateway - Development Environment"
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  up          Start development environment (force-recreate, pull latest, remove orphans)"
        echo "  down        Stop development environment (preserves data, removes orphans)"
        echo "              --clean  ⚠️  DESTRUCTIVE: Remove all data (requires confirmation)"
        echo "  reset       Restart environment preserving data (down + up + bootstrap)"
        echo "              --clean  ⚠️  DESTRUCTIVE: Full reset with data removal (requires confirmation)"
        echo "  build       Build APISIX container (default: no-cache + pull latest base)"
        echo "              --cache   Use cache (faster for minor changes)"
        echo "  status      Show environment status"
        echo "  logs        Show logs for all services"
        echo "              [service] Show logs for specific service"
        echo "              --follow  Follow log output"
        echo "  routes      List configured APISIX routes"
        echo "  bootstrap   Load routes into APISIX"
        echo "  help        Show this help message"
        echo
        echo "Lifecycle guarantees:"
        echo "  - 'up' always uses: --pull always --force-recreate --remove-orphans"
        echo "  - 'build' always uses: --no-cache --pull (unless --cache specified)"
        echo "  - 'down' always uses: --remove-orphans"
        echo "  This ensures running containers always match the current code."
        echo
        echo "⚠️  DESTRUCTIVE OPERATIONS (will delete all consumers and data):"
        echo "  - down --clean"
        echo "  - reset --clean"
        echo
        echo "Examples:"
        echo "  $0 reset            # Restart environment (keeps data)"
        echo "  $0 reset --clean    # Full reset (⚠️  DELETES ALL DATA)"
        echo "  $0 build            # Rebuild APISIX (clean, no cache)"
        echo "  $0 build --cache    # Rebuild APISIX (with cache, faster)"
        echo "  $0 logs apisix -f   # Follow APISIX logs"
        echo "  $0 routes           # List all routes"
        ;;
esac