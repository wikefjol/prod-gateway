#!/usr/bin/env bash
set -euo pipefail

# Gateway control script - manages apisix + portal services
# Usage: ./infra/ctl/ctl.sh [command] [service] [options]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INFRA="$ROOT/infra"
SERVICES_DIR="$ROOT/services"

# Available services (in dependency order)
CORE_SERVICES=(apisix portal)

# Default to dev environment
ENV_NAME="${GATEWAY_ENV:-dev}"

# Parse global flags
CLEAN_MODE=""
for arg in "$@"; do
  case "$arg" in
    --test|-t) ENV_NAME="test" ;;
    --clean) CLEAN_MODE="1" ;;
  esac
done

# Remove flags from args
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --test|-t|--clean) ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"

CMD="${1:-help}"
shift || true

# Service argument (optional - defaults to all for up/down, required for some commands)
SVC="${1:-}"
[[ "$SVC" =~ ^(apisix|portal|swag|docs)$ ]] && shift || SVC=""

ENV_FILE="$INFRA/env/.env.$ENV_NAME"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Missing env file: $ENV_FILE" >&2
  exit 1
fi

# Load env vars
set -a
source "$ENV_FILE"
set +a

# Validate required env vars
: "${ADMIN_KEY:?ADMIN_KEY missing - set in environment or .env.local}"

ensure_network() {
  : "${CORE_NET:?CORE_NET must be set in env file}"
  if ! docker network inspect "$CORE_NET" >/dev/null 2>&1; then
    echo "Creating network: $CORE_NET"
    docker network create "$CORE_NET" >/dev/null
  fi
}

# Compose command for a specific service
dc() {
  local svc="$1"
  shift
  local compose_file="$SERVICES_DIR/$svc/compose.yaml"
  if [[ ! -f "$compose_file" ]]; then
    echo "Error: No compose.yaml for service: $svc" >&2
    return 1
  fi
  docker compose \
    -p "gw-${ENV_NAME}-${svc}" \
    --env-file "$ENV_FILE" \
    -f "$compose_file" \
    "$@"
}

# Check if service is running
is_running() {
  local svc="$1"
  dc "$svc" ps --services --filter "status=running" 2>/dev/null | grep -q .
}

confirm_delete() {
  echo "DESTRUCTIVE: This will delete volumes and data."
  echo "Type DELETE to confirm:"
  read -r x
  [[ "$x" == "DELETE" ]]
}

# Git info helpers
print_git_info() {
  local sha branch dirty
  sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
  dirty=""
  if ! git -C "$ROOT" diff --quiet 2>/dev/null; then dirty=" (dirty)"; fi
  echo "Git: $branch @ $sha$dirty"
}

print_running_info() {
  local cid image_id
  cid="$(dc apisix ps -q apisix 2>/dev/null)"
  if [[ -n "$cid" ]]; then
    image_id="$(docker inspect --format='{{.Image}}' "$cid" 2>/dev/null | cut -c8-19)"
    echo "Image: ${image_id:-unknown}"
  else
    echo "Image: not running"
  fi
  echo "Admin: http://localhost:${APISIX_ADMIN_PORT:-9180}"
}

# Health polling (portable, doesn't depend on compose version)
wait_for_healthy() {
  local timeout="${1:-90}"
  local start=$SECONDS
  echo "Waiting for healthy (${timeout}s timeout)..."
  while (( SECONDS - start < timeout )); do
    if curl -sf "http://localhost:${APISIX_GATEWAY_PORT:-9080}/health" >/dev/null 2>&1; then
      echo "Healthy after $((SECONDS - start))s"
      return 0
    fi
    sleep 2
  done
  echo "ERROR: Health check timeout after ${timeout}s" >&2
  dc apisix logs --tail=100
  return 1
}

# Assert running revision matches expected (ghost killer)
assert_revision() {
  local expected="$1"
  local actual
  actual="$(curl -sI "http://localhost:${APISIX_GATEWAY_PORT:-9080}/health" 2>/dev/null | grep -i X-Gateway-Revision | awk '{print $2}' | tr -d '\r')"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: Revision mismatch! Expected: $expected, Got: ${actual:-<none>}" >&2
    echo "The running gateway does not match your code. Try: ./infra/ctl/ctl.sh dev --no-cache" >&2
    return 1
  fi
  echo "Revision verified: $actual"
}

# SWAG health polling
wait_for_swag() {
  local timeout="${1:-120}"
  local start=$SECONDS
  echo "Waiting for SWAG healthy (${timeout}s timeout)..."
  while (( SECONDS - start < timeout )); do
    if curl -sfk "https://localhost" >/dev/null 2>&1; then
      echo "SWAG healthy after $((SECONDS - start))s"
      return 0
    fi
    sleep 3
  done
  echo "ERROR: SWAG health check timeout after ${timeout}s" >&2
  dc swag logs --tail=50
  return 1
}

# Start service(s)
cmd_up() {
  local build_flag="" no_cache=""
  local services=()
  for arg in "$@"; do
    case "$arg" in
      --build) build_flag="--build" ;;
      --no-cache) no_cache="1" ;;
      *) services+=("$arg") ;;
    esac
  done
  [[ ${#services[@]} -eq 0 ]] && services=("${CORE_SERVICES[@]}")

  # --no-cache requires explicit build first (compose up doesn't support it)
  if [[ -n "$no_cache" ]]; then
    for svc in "${services[@]}"; do
      echo "Building $svc (no cache)..."
      dc "$svc" build --pull --no-cache
    done
    build_flag=""
  fi

  ensure_network
  for svc in "${services[@]}"; do
    echo "Starting $svc..."
    dc "$svc" up -d --force-recreate --remove-orphans $build_flag
    echo "✅ $svc started"
  done
}

# Stop service(s)
cmd_down() {
  local services=("${@:-${CORE_SERVICES[@]}}")
  for svc in "${services[@]}"; do
    echo "Stopping $svc..."
    dc "$svc" down --remove-orphans
  done
}

# Build service(s)
cmd_build() {
  local services=("${@:-${CORE_SERVICES[@]}}")
  for svc in "${services[@]}"; do
    echo "Building $svc..."
    dc "$svc" build
  done
}

# Rebuild with --no-cache
cmd_rebuild() {
  local svc="${1:-apisix}"
  ensure_network
  echo "Rebuilding $svc with --no-cache..."
  dc "$svc" build --pull --no-cache
  echo "Restarting $svc..."
  dc "$svc" up -d --force-recreate --remove-orphans
  echo "✅ Rebuild complete."
}

# Dev command - canonical way to get to known-good state
cmd_dev() {
  local no_cache="" nuke="" with_portal="" with_swag=""
  for arg in "$@"; do
    case "$arg" in
      --no-cache) no_cache="1" ;;
      --nuke) nuke="1" ;;
      --with-portal) with_portal="1" ;;
      --with-swag) with_swag="1" ;;
    esac
  done

  local git_sha
  git_sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  export GIT_SHA="$git_sha"

  echo "=== Gateway Dev Refresh ==="
  print_git_info
  ensure_network

  # Stop apisix only (not portal/swag) unless flagged
  echo "Stopping apisix..."
  dc apisix down --remove-orphans 2>/dev/null || true
  [[ -n "$with_portal" ]] && { dc portal down --remove-orphans 2>/dev/null || true; }
  [[ -n "$with_swag" ]] && { dc swag down --remove-orphans 2>/dev/null || true; }

  if [[ -n "$nuke" ]]; then
    echo "NUKE MODE: will delete etcd data (fresh state)"
    confirm_delete || exit 1
    dc apisix down -v --remove-orphans 2>/dev/null || true
  fi

  # Build
  echo "Building apisix..."
  local build_args=(--build-arg "GIT_SHA=$git_sha")
  [[ -n "$no_cache" ]] && build_args+=(--pull --no-cache)
  dc apisix build "${build_args[@]}"
  [[ -n "$with_portal" ]] && dc portal build ${no_cache:+--pull --no-cache}

  # Start
  echo "Starting apisix..."
  dc apisix up -d --force-recreate --remove-orphans
  [[ -n "$with_portal" ]] && dc portal up -d --force-recreate --remove-orphans
  [[ -n "$with_swag" ]] && dc swag up -d --force-recreate --remove-orphans

  # Wait for healthy (portable polling, not --wait)
  if ! wait_for_healthy 90; then
    exit 1
  fi

  # Bootstrap (includes version header)
  echo "Bootstrapping..."
  "$ROOT/services/apisix/scripts/bootstrap.sh" || { echo "Bootstrap failed" >&2; exit 1; }

  # Assert revision matches (ghost killer)
  if ! assert_revision "$git_sha"; then
    exit 1
  fi

  # Wait for SWAG if started
  if [[ -n "$with_swag" ]]; then
    if ! wait_for_swag 120; then
      exit 1
    fi
  fi

  echo "=== Ready ==="
  print_git_info
  print_running_info
}

case "$CMD" in
  up)
    if [[ -n "$CLEAN_MODE" ]]; then
      echo "Clean mode: removing apisix volumes (etcd data)..."
      confirm_delete || exit 1
      dc apisix down -v --remove-orphans 2>/dev/null || true
    fi
    if [[ -n "$SVC" ]]; then
      cmd_up "$SVC" "$@"
    else
      cmd_up "${CORE_SERVICES[@]}" "$@"
    fi
    echo "Gateway ready. Admin: http://localhost:${APISIX_ADMIN_PORT:-9180}"
    ;;

  down)
    if [[ -n "$CLEAN_MODE" ]]; then
      confirm_delete || exit 1
      for svc in portal apisix; do
        dc "$svc" down -v --remove-orphans 2>/dev/null || true
      done
    elif [[ -n "$SVC" ]]; then
      cmd_down "$SVC"
    else
      cmd_down portal apisix
    fi
    ;;

  build)
    if [[ -n "$SVC" ]]; then
      cmd_build "$SVC"
    else
      cmd_build "${CORE_SERVICES[@]}"
    fi
    ;;

  rebuild)
    cmd_rebuild "${SVC:-apisix}"
    ;;

  dev)
    cmd_dev "$@"
    ;;

  restart)
    if [[ -n "$SVC" ]]; then
      dc "$SVC" restart "$@"
    else
      for svc in "${CORE_SERVICES[@]}"; do
        dc "$svc" restart
      done
    fi
    ;;

  reset)
    echo "DEPRECATED: 'reset' is now an alias for 'dev'. Use 'dev' directly." >&2
    cmd_dev "$@"
    ;;

  logs)
    target="${SVC:-apisix}"
    dc "$target" logs "$@"
    ;;

  ps|status)
    for svc in "${CORE_SERVICES[@]}" swag; do
      echo "=== $svc ==="
      dc "$svc" ps 2>/dev/null || echo "(not running)"
    done
    ;;

  exec)
    target="${SVC:-apisix}"
    dc "$target" exec "$target" "$@"
    ;;

  shell)
    target="${SVC:-apisix}"
    dc "$target" exec "$target" sh
    ;;

  routes)
    VERBOSE=""
    for arg in "$@"; do
      case "$arg" in --verbose|-v) VERBOSE="1" ;; esac
    done
    if [[ -n "$VERBOSE" ]]; then
      curl -s "http://localhost:${APISIX_ADMIN_PORT:-9180}/apisix/admin/routes" \
        -H "X-API-KEY: ${ADMIN_KEY}" | python3 -m json.tool 2>/dev/null || \
        echo "Failed to fetch routes. Is gateway running?"
    else
      curl -s "http://localhost:${APISIX_ADMIN_PORT:-9180}/apisix/admin/routes" \
        -H "X-API-KEY: ${ADMIN_KEY}" | python3 -c "import sys,json
d=json.load(sys.stdin)
fmt='{:<30} {:<20} {}'
print(fmt.format('ID','METHODS','URI'))
print('-'*80)
for r in d.get('list',[]):
    v=r['value']
    methods=','.join(v.get('methods') or ['*'])
    print(fmt.format(v.get('id','?'), methods, v.get('uri','?')))
" 2>/dev/null || echo "Failed to fetch routes. Is gateway running?"
    fi
    ;;

  bootstrap)
    export GIT_SHA="${GIT_SHA:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
    "$ROOT/services/apisix/scripts/bootstrap.sh" ${CLEAN_MODE:+--clean} "$ENV_NAME" "$@" || echo "Bootstrap failed"
    ;;

  help|*)
    cat <<EOF
Gateway Control Script

Usage: ./infra/ctl/ctl.sh [command] [service] [options]

=== RECOMMENDED ===
  dev                 Build + start + bootstrap + verify revision
                      --no-cache     Force fresh build (cache-bust)
                      --with-portal  Also manage portal service
                      --with-swag    Also manage SWAG reverse proxy
                      --nuke         Delete etcd volume (fresh state, DELETE confirm)

=== Other Commands ===
  up [service]        Start (may use stale image)
  down [service]      Stop
  build [service]     Build (may use cache)
  rebuild [service]   Build --no-cache + restart (single svc)
  restart [service]   [WARN: reuses old container]
  reset               DEPRECATED - use 'dev'
  logs [service] [-f] View logs (default: apisix)
  ps/status           Show status of all services
  exec [service] cmd  Run command in container (default: apisix)
  shell [service]     Open shell in container (default: apisix)
  routes [-v]         List routes (default: compact table; -v: full JSON)
  bootstrap           Load routes into APISIX (additive)

Services: ${CORE_SERVICES[*]}

Options:
  --clean             Clean mode (context-dependent, requires confirmation):
                        up --clean      Remove etcd volume, fresh start
                        down --clean    Stop + remove all volumes
                        bootstrap --clean  Delete all routes first
  --test, -t          Use test environment (different ports)

Environment:
  GATEWAY_ENV         Set environment (dev|test), default: dev

Examples:
  ./infra/ctl/ctl.sh dev                   # Build + start + bootstrap + verify
  ./infra/ctl/ctl.sh dev --no-cache        # Cache-bust build
  ./infra/ctl/ctl.sh dev --with-portal     # Full stack
  ./infra/ctl/ctl.sh dev --with-swag       # Include SWAG reverse proxy
  ./infra/ctl/ctl.sh dev --nuke            # Fresh etcd state
  ./infra/ctl/ctl.sh up swag               # Start SWAG only
  ./infra/ctl/ctl.sh logs apisix -f        # Follow apisix logs
EOF
    ;;
esac
