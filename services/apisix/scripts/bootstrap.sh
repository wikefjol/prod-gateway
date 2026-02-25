#!/bin/bash
# APISIX Bootstrap - Loads consumer groups + routes into APISIX
# Usage: ./services/apisix/scripts/bootstrap.sh [--clean] [dev|test]

set -euo pipefail

# -------------------------
# Configuration
# -------------------------
CLEAN_ROUTES=false

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN_ROUTES=true ;;
  esac
done

# Filter out flags to get environment
ENVIRONMENT="dev"
for arg in "$@"; do
  case "$arg" in
    --*) ;;
    *) ENVIRONMENT="$arg" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SERVICE_DIR/../.." && pwd)"

ROUTES_DIR="$SERVICE_DIR/routes"
CONSUMER_GROUPS_DIR="$SERVICE_DIR/consumer-groups"
PLUGIN_METADATA_DIR="$SERVICE_DIR/plugin-metadata"

# -------------------------
# Logging helpers
# -------------------------
log_info()    { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_error()   { echo "❌ $*" >&2; }

# -------------------------
# Load environment variables
# -------------------------
ENV_FILE="$PROJECT_ROOT/infra/env/.env.$ENVIRONMENT"
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
: "${APISIX_ADMIN_PORT:?APISIX_ADMIN_PORT missing in $ENV_FILE}"
ADMIN_API="http://127.0.0.1:${APISIX_ADMIN_PORT}/apisix/admin"

# -------------------------
# Dependency checks
# -------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log_error "Missing dependency: $1"; exit 1; }
}

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

# LLM Gateway routes (new /llm/* namespace)
LLM_ROUTES=(
  # ai-proxy (APISIX-native routing)
  "llm-ai-proxy-chat-openai.json"
  "llm-ai-proxy-chat-anthropic.json"
  "llm-ai-proxy-models.json"
  # Claude Code sidecar (native Anthropic, restricted to claude_code_users)
  "llm-claude-code-messages.json"
  "llm-claude-code-count-tokens.json"
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
# Clean all routes (--clean flag)
# -------------------------
clean_all_routes() {
  log_info "Cleaning all existing routes..."

  local route_ids
  route_ids=$(curl -s "$ADMIN_API/routes" -H "X-API-KEY: $ADMIN_KEY" | \
    jq -r '.list[].value.id // empty' 2>/dev/null)

  if [ -z "$route_ids" ]; then
    log_info "No routes to clean"
    return 0
  fi

  local count=0
  for id in $route_ids; do
    curl -s -X DELETE "$ADMIN_API/routes/$id" -H "X-API-KEY: $ADMIN_KEY" >/dev/null
    count=$((count + 1))
  done

  log_success "Deleted $count routes"
}

# -------------------------
# Generic APISIX apply helper
# -------------------------
apisix_apply_json() {
  local kind="$1"
  local endpoint="$2"
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
  apisix_apply_json "consumer-group" "consumer_groups" "$group_path" "true" "false"
}

load_route() {
  local route_file="$1"
  local route_path="$ROUTES_DIR/$route_file"
  apisix_apply_json "route" "routes" "$route_path" "false" "true"
}

load_plugin_metadata() {
  local metadata_file="$1"
  local metadata_path="$PLUGIN_METADATA_DIR/$metadata_file"

  if [ ! -f "$metadata_path" ]; then
    log_error "Plugin metadata file not found: $metadata_path"
    return 1
  fi

  local plugin_name payload response http_code body
  plugin_name="$(jq -r '.id // empty' "$metadata_path" 2>/dev/null || true)"
  payload="$(envsubst '${ENVIRONMENT}' < "$metadata_path")"

  if [ -z "$plugin_name" ]; then
    log_error "Plugin metadata JSON missing required .id: $metadata_path"
    return 1
  fi

  log_info "Applying plugin_metadata (PUT): $(basename "$metadata_path") (plugin=$plugin_name)"
  response="$(curl -sS -w "\n%{http_code}" -X PUT "$ADMIN_API/plugin_metadata/$plugin_name" \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -d "$payload")"

  http_code="$(tail -n1 <<<"$response")"
  body="$(sed '$d' <<<"$response")"

  if [[ "$http_code" =~ ^(200|201)$ ]]; then
    log_success "Applied plugin_metadata: $(basename "$metadata_path")"
    return 0
  else
    log_error "Failed plugin_metadata: $(basename "$metadata_path") (HTTP $http_code)"
    echo "$body" >&2
    return 1
  fi
}

# -------------------------
# Version Header (global rule)
# -------------------------
bootstrap_version_header() {
  local git_sha="${GIT_SHA:-unknown}"
  log_info "Setting X-Gateway-Revision header: $git_sha"

  local payload
  payload=$(cat <<EOF
{
  "plugins": {
    "response-rewrite": {
      "headers": {
        "set": {
          "X-Gateway-Revision": "$git_sha"
        }
      }
    }
  }
}
EOF
)

  local response http_code
  response="$(curl -sS -w "\n%{http_code}" -X PUT "$ADMIN_API/global_rules/9999" \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -d "$payload")"

  http_code="$(tail -n1 <<<"$response")"
  if [[ "$http_code" =~ ^(200|201)$ ]]; then
    log_success "Version header configured: $git_sha"
  else
    log_error "Failed to set version header (HTTP $http_code)"
    return 1
  fi
}

# -------------------------
# Bootstrap steps
# -------------------------

PLUGIN_METADATA_FILES=(
  "file-logger.json"
)

bootstrap_plugin_metadata() {
  log_info "Loading plugin metadata..."
  local ok=0 fail=0

  for metadata in "${PLUGIN_METADATA_FILES[@]}"; do
    if load_plugin_metadata "$metadata"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done

  log_info "Loaded $ok/${#PLUGIN_METADATA_FILES[@]} plugin metadata"

  if [ "$fail" -ne 0 ]; then
    log_error "Plugin metadata bootstrap failed ($fail failures)"
    return 1
  fi
  return 0
}

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

bootstrap_llm_routes() {
  if [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    log_info "Loading LLM routes (API keys detected)..."
    local ok=0 fail=0

    for route in "${LLM_ROUTES[@]}"; do
      if load_route "$route"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done

    log_info "Loaded $ok/${#LLM_ROUTES[@]} LLM routes"

    if [ "$fail" -ne 0 ]; then
      log_error "Some LLM routes failed to load ($fail failures). Continuing."
    fi
  else
    log_info "Skipping LLM routes (no API keys found)"
  fi
}

# -------------------------
# Main
# -------------------------
main() {
  log_info "Bootstrapping APISIX for $ENVIRONMENT environment..."

  require_cmd curl
  require_cmd jq
  require_cmd envsubst

  if ! wait_for_apisix; then
    exit 1
  fi

  # Set version header (global rule) - do this first for observability
  if ! bootstrap_version_header; then
    log_error "Failed to set version header, continuing anyway..."
  fi

  # Clean routes if --clean flag was passed
  if [ "$CLEAN_ROUTES" = true ]; then
    clean_all_routes
  fi

  if ! bootstrap_consumer_groups; then
    exit 1
  fi

  if ! bootstrap_plugin_metadata; then
    exit 1
  fi

  if ! bootstrap_core_routes; then
    exit 1
  fi

  bootstrap_llm_routes

  log_success "Bootstrap completed for $ENVIRONMENT environment"
}

main "$@"
