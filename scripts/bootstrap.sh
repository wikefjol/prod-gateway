#!/bin/bash
# APISIX Bootstrap - Single-File, Scalable
# Loads required consumer groups + essential routes into APISIX
# Usage: ./scripts/bootstrap.sh [dev|test]

set -euo pipefail

# -------------------------
# Configuration
# -------------------------
ENVIRONMENT="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROUTES_DIR="$PROJECT_ROOT/apisix/routes"
CONSUMER_GROUPS_DIR="$PROJECT_ROOT/apisix/consumer-groups"

# Environment-specific admin API endpoints (host-side)
if [ "$ENVIRONMENT" = "test" ]; then
  ADMIN_API="http://127.0.0.1:9181/apisix/admin"
else
  ADMIN_API="http://127.0.0.1:9180/apisix/admin"
fi

# -------------------------
# Logging helpers
# -------------------------
log_info()    { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_error()   { echo "❌ $*" >&2; }

# -------------------------
# Dependency checks
# -------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log_error "Missing dependency: $1"; exit 1; }
}

# -------------------------
# Load environment variables from secrets
# -------------------------
ENV_FILE="$PROJECT_ROOT/.env.$ENVIRONMENT"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  log_error "Missing env file: $ENV_FILE"
  exit 1
fi

: "${ADMIN_KEY:?ADMIN_KEY missing in $ENV_FILE}"

# -------------------------
# Resources to bootstrap
# -------------------------

# Required consumer groups (must exist before portal creates consumers with group_id)
CORE_CONSUMER_GROUPS=(
  "base-user-group.json"
  "premium-user-group.json"
)

# Core routes (always deployed)
CORE_ROUTES=(
  "health-route.json"
  "portal-redirect-route.json"
  "oidc-generic-route.json"
  "root-redirect-route.json"
)

# Provider routes (optional; gated by API keys)
PROVIDER_ROUTES=(
  "anthropic-route.json"
  "openai-route.json"
  "litellm-route.json"
)

# -------------------------
# Wait for APISIX admin API
# -------------------------
wait_for_apisix() {
  log_info "Waiting for APISIX admin API..."
  for _ in {1..30}; do
    if curl -s -f "$ADMIN_API/routes" -H "X-API-KEY: $ADMIN_KEY" >/dev/null 2>&1; then
      log_success "APISIX admin API is ready"
      return 0
    fi
    sleep 2
  done
  log_error "APISIX admin API failed to become ready"
  return 1
}

# -------------------------
# Generic APISIX apply helper
# -------------------------
# usage: apisix_apply_json <kind> <endpoint> <file_path> <require_id:true|false> <allow_post:true|false>
apisix_apply_json() {
  local kind="$1"         # "route" / "consumer-group" / etc
  local endpoint="$2"     # "routes" / "consumer_groups"
  local file_path="$3"
  local require_id="${4:-true}"
  local allow_post="${5:-false}"

  if [ ! -f "$file_path" ]; then
    log_error "$kind file not found: $file_path"
    return 1
  fi

  local id payload response http_code body
  id="$(jq -r '.id // empty' "$file_path" 2>/dev/null || true)"
  payload="$(envsubst < "$file_path")"

  if [ -z "$id" ] && [ "$require_id" = "true" ]; then
    log_error "$kind JSON missing required .id: $file_path"
    return 1
  fi

  if [ -n "$id" ]; then
    log_info "Applying $kind (PUT): $(basename "$file_path") (id=$id)"
    response="$(curl -sS -w "\n%{http_code}" -X PUT "$ADMIN_API/$endpoint/$id" \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -d "$payload")"
  else
    if [ "$allow_post" != "true" ]; then
      log_error "$kind JSON has no .id and POST not allowed: $file_path"
      return 1
    fi

    log_info "Applying $kind (POST): $(basename "$file_path")"
    response="$(curl -sS -w "\n%{http_code}" -X POST "$ADMIN_API/$endpoint" \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -d "$payload")"
  fi

  http_code="$(tail -n1 <<<"$response")"
  body="$(sed '$d' <<<"$response")"

  if [[ "$http_code" =~ ^(200|201)$ ]]; then
    log_success "Applied $kind: $(basename "$file_path")"
    return 0
  else
    log_error "Failed $kind: $(basename "$file_path") (HTTP $http_code)"
    echo "$body" >&2
    return 1
  fi
}

# -------------------------
# Resource loaders
# -------------------------
load_consumer_group() {
  local group_file="$1"
  local group_path="$CONSUMER_GROUPS_DIR/$group_file"
  # Consumer groups MUST have .id and should be PUT by ID
  apisix_apply_json "consumer-group" "consumer_groups" "$group_path" "true" "false"
}

load_route() {
  local route_file="$1"
  local route_path="$ROUTES_DIR/$route_file"
  # Routes may be POSTed if no .id, or PUT if .id exists
  apisix_apply_json "route" "routes" "$route_path" "false" "true"
}

# -------------------------
# Bootstrap steps
# -------------------------
bootstrap_consumer_groups() {
  log_info "Loading consumer groups..."
  local ok=0 fail=0

  for group in "${CORE_CONSUMER_GROUPS[@]}"; do
    if load_consumer_group "$group"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done

  log_info "Loaded $ok/${#CORE_CONSUMER_GROUPS[@]} consumer groups"

  if [ "$fail" -ne 0 ]; then
    log_error "Consumer group bootstrap failed ($fail failures)"
    return 1
  fi
  return 0
}

bootstrap_core_routes() {
  log_info "Loading core routes..."
  local ok=0 fail=0

  for route in "${CORE_ROUTES[@]}"; do
    if load_route "$route"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done

  log_info "Loaded $ok/${#CORE_ROUTES[@]} core routes"

  if [ "$fail" -ne 0 ]; then
    log_error "Core route bootstrap failed ($fail failures)"
    return 1
  fi
  return 0
}

bootstrap_provider_routes_if_configured() {
  # Only attempt provider routes if API keys are available
  if [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${LITELLM_KEY:-}" ]; then
    log_info "Loading provider routes (API keys detected)..."
    local ok=0 fail=0

    for route in "${PROVIDER_ROUTES[@]}"; do
      if load_route "$route"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done

    log_info "Loaded $ok/${#PROVIDER_ROUTES[@]} provider routes"

    # Provider routes are optional; don't hard-fail by default
    if [ "$fail" -ne 0 ]; then
      log_error "Some provider routes failed to load ($fail failures). Continuing."
    fi
  else
    log_info "Skipping provider routes (no API keys found)"
  fi
}

# -------------------------
# Main
# -------------------------
main() {
  log_info "Bootstrapping APISIX for $ENVIRONMENT environment..."

  cd "$PROJECT_ROOT"

  require_cmd curl
  require_cmd jq
  require_cmd envsubst

  if ! wait_for_apisix; then
    exit 1
  fi

  # Required: consumer groups first (portal depends on base_user/premium_user)
  if ! bootstrap_consumer_groups; then
    exit 1
  fi

  # Required: core routes
  if ! bootstrap_core_routes; then
    exit 1
  fi

  # Optional: provider routes
  bootstrap_provider_routes_if_configured

  log_success "Bootstrap completed for $ENVIRONMENT environment"
}

main "$@"
