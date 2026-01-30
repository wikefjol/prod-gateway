#!/bin/bash
# APISIX Gateway - Unified Control Script
# Usage: ./infra/ctl/ctl.sh [--test|-t] <command> [service] [options]

set -euo pipefail

# -------------------------
# Configuration
# -------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVICES_DIR="$PROJECT_ROOT/services"

# Default environment
ENV="dev"

# Parse --test flag
if [[ "${1:-}" == "--test" || "${1:-}" == "-t" ]]; then
  ENV="test"
  shift
fi

ENV_FILE="$PROJECT_ROOT/infra/env/.env.$ENV"

# -------------------------
# Load environment
# -------------------------
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Env file not found: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${CORE_NET:?CORE_NET missing in $ENV_FILE}"
: "${ADMIN_KEY:?ADMIN_KEY missing in $ENV_FILE}"

# -------------------------
# Helpers
# -------------------------
log_info()    { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_error()   { echo "❌ $*" >&2; }
log_warning() { echo "⚠️  $*"; }

# Core services in dependency order
CORE_SERVICES=(etcd apisix portal)

# Ensure network exists
ensure_network() {
  if ! docker network inspect "$CORE_NET" >/dev/null 2>&1; then
    log_info "Creating network: $CORE_NET"
    docker network create "$CORE_NET"
  fi
}

# Get compose command for a service
compose_cmd() {
  local svc="$1"
  shift
  docker compose --project-name "apisix-$ENV-$svc" \
    --env-file "$ENV_FILE" \
    -f "$SERVICES_DIR/$svc/compose.yaml" \
    "$@"
}

# Check if service is running
is_running() {
  local svc="$1"
  compose_cmd "$svc" ps --services --filter "status=running" 2>/dev/null | grep -q "$svc"
}

# Wait for APISIX admin API
wait_for_apisix() {
  local port="${APISIX_ADMIN_PORT:-9180}"
  log_info "Waiting for APISIX admin API on port $port..."
  for _ in {1..30}; do
    if curl -s -f "http://127.0.0.1:$port/apisix/admin/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; then
      log_success "APISIX admin API is ready"
      return 0
    fi
    sleep 2
  done
  log_error "APISIX admin API failed to become ready"
  return 1
}

# Confirm destructive operation
confirm_destructive() {
  local op="$1"
  echo
  log_warning "DESTRUCTIVE: $op"
  log_warning "This will DELETE ALL DATA"
  echo "Type DELETE to confirm:"
  read -r confirm
  if [ "$confirm" != "DELETE" ]; then
    log_error "Cancelled"
    exit 1
  fi
}

# -------------------------
# Commands
# -------------------------

cmd_up() {
  local svc="${1:-}"
  ensure_network

  if [ -z "$svc" ]; then
    # Start all core services
    for s in "${CORE_SERVICES[@]}"; do
      cmd_up "$s"
    done
    return
  fi

  if [ ! -d "$SERVICES_DIR/$svc" ]; then
    log_error "Unknown service: $svc"
    exit 1
  fi

  log_info "Starting $svc..."
  compose_cmd "$svc" up -d --pull always --force-recreate --remove-orphans
  log_success "$svc started"
}

cmd_down() {
  local svc="${1:-}"
  local clean="${2:-}"

  if [ -z "$svc" ]; then
    # Stop all in reverse order
    for s in $(printf '%s\n' "${CORE_SERVICES[@]}" | tac); do
      cmd_down "$s" "$clean"
    done
    return
  fi

  if [ ! -d "$SERVICES_DIR/$svc" ]; then
    log_error "Unknown service: $svc"
    exit 1
  fi

  log_info "Stopping $svc..."
  if [ "$clean" == "--clean" ]; then
    confirm_destructive "down $svc --clean"
    compose_cmd "$svc" down -v --remove-orphans
    log_success "$svc stopped (data removed)"
  else
    compose_cmd "$svc" down --remove-orphans
    log_success "$svc stopped"
  fi
}

cmd_reset() {
  local svc="${1:-}"
  local clean="${2:-}"

  if [ "$clean" == "--clean" ]; then
    cmd_down "$svc" --clean
  else
    cmd_down "$svc"
  fi
  cmd_up "$svc"

  # Bootstrap after apisix comes up
  if [ -z "$svc" ] || [ "$svc" == "apisix" ]; then
    if wait_for_apisix; then
      cmd_bootstrap
    fi
  fi
}

cmd_logs() {
  local svc="${1:-}"
  shift || true
  local follow=""

  # Check for -f flag
  for arg in "$@"; do
    if [ "$arg" == "-f" ] || [ "$arg" == "--follow" ]; then
      follow="-f"
    fi
  done

  if [ -z "$svc" ]; then
    log_error "Usage: ctl logs <service> [-f]"
    exit 1
  fi

  if [ ! -d "$SERVICES_DIR/$svc" ]; then
    log_error "Unknown service: $svc"
    exit 1
  fi

  compose_cmd "$svc" logs $follow "$svc"
}

cmd_status() {
  log_info "Environment: $ENV (network: $CORE_NET)"
  echo
  for svc in "${CORE_SERVICES[@]}"; do
    if [ -d "$SERVICES_DIR/$svc" ]; then
      if is_running "$svc"; then
        echo "  ✅ $svc: running"
      else
        echo "  ⬚  $svc: stopped"
      fi
    fi
  done
}

cmd_routes() {
  local port="${APISIX_ADMIN_PORT:-9180}"
  if ! curl -s -f "http://127.0.0.1:$port/apisix/admin/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; then
    log_error "APISIX admin API not accessible"
    exit 1
  fi

  log_info "Routes:"
  curl -s "http://127.0.0.1:$port/apisix/admin/routes" -H "X-API-KEY: $ADMIN_KEY" | \
    jq -r '.list[] | "  \(.value.id // "?") - \(.value.name // "unnamed") [\(.value.uri // .value.uris[0] // "no-uri")]"' 2>/dev/null || \
    curl -s "http://127.0.0.1:$port/apisix/admin/routes" -H "X-API-KEY: $ADMIN_KEY"
}

cmd_bootstrap() {
  if ! wait_for_apisix; then
    log_error "Cannot bootstrap: APISIX not healthy"
    exit 1
  fi

  log_info "Running bootstrap..."
  "$SERVICES_DIR/apisix/scripts/bootstrap.sh" "$ENV"
}

cmd_build() {
  local svc="${1:-}"
  local cache="${2:-}"

  if [ -z "$svc" ]; then
    log_error "Usage: ctl build <service> [--cache]"
    exit 1
  fi

  if [ ! -d "$SERVICES_DIR/$svc" ]; then
    log_error "Unknown service: $svc"
    exit 1
  fi

  log_info "Building $svc..."
  if [ "$cache" == "--cache" ]; then
    compose_cmd "$svc" build --pull
  else
    compose_cmd "$svc" build --no-cache --pull
  fi
  log_success "$svc built"
}

cmd_help() {
  cat <<EOF
APISIX Gateway Control Script

Usage: ./infra/ctl/ctl.sh [--test|-t] <command> [service] [options]

Environment:
  Default: dev
  --test, -t    Use test environment

Commands:
  up [service]              Start service(s) (default: all core)
  down [service] [--clean]  Stop service(s); --clean removes volumes
  reset [service] [--clean] Restart service(s) + bootstrap
  logs <service> [-f]       View logs
  status                    Show status of all services
  routes                    List APISIX routes
  bootstrap                 Load routes into APISIX
  build <service> [--cache] Build service

Core services: etcd apisix portal

Examples:
  ./infra/ctl/ctl.sh up                    # Start all dev services
  ./infra/ctl/ctl.sh up apisix             # Start only apisix
  ./infra/ctl/ctl.sh -t up                 # Start all test services
  ./infra/ctl/ctl.sh reset                 # Restart + bootstrap
  ./infra/ctl/ctl.sh logs apisix -f        # Follow apisix logs
  ./infra/ctl/ctl.sh down --clean          # Stop all + remove data
EOF
}

# -------------------------
# Main
# -------------------------
case "${1:-help}" in
  up)        shift; cmd_up "$@" ;;
  down)      shift; cmd_down "$@" ;;
  reset)     shift; cmd_reset "$@" ;;
  logs)      shift; cmd_logs "$@" ;;
  status)    cmd_status ;;
  routes)    cmd_routes ;;
  bootstrap) cmd_bootstrap ;;
  build)     shift; cmd_build "$@" ;;
  help|*)    cmd_help ;;
esac
