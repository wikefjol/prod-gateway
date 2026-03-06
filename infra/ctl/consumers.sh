#!/usr/bin/env bash
# Consumer management subcommands for ctl.sh
# Usage: ctl consumers list | move <ids...> --to <group> [--file path] [--dry-run]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INFRA="$ROOT/infra"

ENV_NAME="${GATEWAY_ENV:-dev}"
for arg in "$@"; do
  case "$arg" in --test|-t) ENV_NAME="test" ;; esac
done

ENV_FILE="$INFRA/env/.env.$ENV_NAME"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Missing env file: $ENV_FILE" >&2
  exit 1
fi
set -a; source "$ENV_FILE"; set +a
: "${ADMIN_KEY:?ADMIN_KEY missing}"

ADMIN_URL="http://localhost:${APISIX_ADMIN_PORT:-9180}/apisix/admin"

# -------------------------
# Helpers
# -------------------------
log_info()    { echo "  $*"; }
log_success() { echo "  $*"; }
log_error()   { echo "  $*" >&2; }

apisix_get() {
  local resp
  resp="$(curl -sf "${ADMIN_URL}/$1" -H "X-API-KEY: ${ADMIN_KEY}")" || {
    log_error "GET /$1 failed"
    return 1
  }
  echo "$resp"
}

apisix_put() {
  local endpoint="$1" payload="$2"
  curl -s -o /dev/null -w '%{http_code}' \
    -X PUT "${ADMIN_URL}/${endpoint}" \
    -H "X-API-KEY: ${ADMIN_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

# Cached consumer list (fetched once)
_CONSUMERS_CACHE=""
fetch_all_consumers() {
  if [[ -z "$_CONSUMERS_CACHE" ]]; then
    _CONSUMERS_CACHE="$(apisix_get consumers)" || return 1
  fi
  echo "$_CONSUMERS_CACHE"
}

validate_group() {
  local group_id="$1"
  if ! apisix_get "consumer_groups/${group_id}" >/dev/null 2>&1; then
    log_error "Consumer group '${group_id}' not found"
    return 1
  fi
}

# -------------------------
# list
# -------------------------
cmd_list() {
  local data
  data="$(apisix_get consumers)" || exit 1

  echo "$data" | jq -r '
    ["OID", "HANDLE", "EMAIL", "GROUP", "CREATED"],
    ["---", "------", "-----", "-----", "-------"],
    (.list // [] | sort_by(.value.username) | .[] | .value |
      (
        (.labels.email // .desc // "") as $email |
        (if $email | contains("@") then ($email | split("@")[0]) else "" end) as $handle |
        (.labels.created_at // "N/A") as $created |
        (.group_id // "none") as $group |
        [.username, $handle, $email, $group, $created]
      )
    ) | @tsv
  ' | column -t -s $'\t'
}

# -------------------------
# move
# -------------------------
cmd_move() {
  local identifiers=() target="" file="" dry_run=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to)      target="${2:?--to requires a group}"; shift 2 ;;
      --file)    file="${2:?--file requires a path}"; shift 2 ;;
      --dry-run) dry_run="1"; shift ;;
      --test|-t) shift ;;  # already handled
      *)         identifiers+=("$1"); shift ;;
    esac
  done

  # Load from file
  if [[ -n "$file" ]]; then
    if [[ ! -f "$file" ]]; then
      log_error "File not found: $file"
      exit 1
    fi
    while IFS= read -r line; do
      line="${line%%#*}"           # strip comments
      line="${line// /}"           # strip whitespace
      [[ -z "$line" ]] && continue
      identifiers+=("$line")
    done < "$file"
  fi

  if [[ -z "$target" ]]; then
    log_error "Missing --to <group>"
    usage
    exit 1
  fi
  if [[ ${#identifiers[@]} -eq 0 ]]; then
    log_error "No identifiers provided"
    usage
    exit 1
  fi

  # Validate target group
  validate_group "$target" || exit 1

  # Fetch all consumers once
  local all
  all="$(fetch_all_consumers)" || exit 1

  local moved=0 skipped=0 failed=0

  for id in "${identifiers[@]}"; do
    local rc=0
    resolve_and_move "$id" "$target" "$dry_run" "$all" || rc=$?
    case $rc in
      0) moved=$((moved + 1)) ;;
      2) skipped=$((skipped + 1)) ;;
      *) failed=$((failed + 1)) ;;
    esac
  done

  echo ""
  echo "moved=$moved skipped=$skipped failed=$failed"
  [[ $failed -gt 0 ]] && exit 1
  exit 0
}

# Resolve identifier → consumer, then move
# Returns: 0=moved, 1=failed, 2=skipped
resolve_and_move() {
  local id="$1" target="$2" dry_run="$3" all="$4"
  local uuid_re='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  local consumer=""

  if [[ "$id" =~ $uuid_re ]]; then
    # OID lookup
    consumer="$(echo "$all" | jq -e --arg oid "$id" \
      '.list[] | select(.value.username == $oid) | .value' 2>/dev/null)"
  elif [[ "$id" == *@* ]]; then
    # Email lookup
    consumer="$(echo "$all" | jq -e --arg email "$id" \
      '[.list[] | select(.value.labels.email == $email) | .value] | if length == 1 then .[0] else empty end' 2>/dev/null)"
    if [[ -z "$consumer" ]]; then
      local count
      count="$(echo "$all" | jq --arg email "$id" \
        '[.list[] | select(.value.labels.email == $email)] | length')"
      if [[ "$count" -gt 1 ]]; then
        log_error "$id: ambiguous ($count matches)"
      else
        log_error "$id: not found"
      fi
      return 1
    fi
  else
    # Try direct username match first
    consumer="$(echo "$all" | jq -e --arg name "$id" \
      '.list[] | select(.value.username == $name) | .value' 2>/dev/null)"
    if [[ -n "$consumer" && "$consumer" != "null" ]]; then
      # found by username, skip handle lookup
      :
    else
    # Handle lookup (email local part)
    consumer=""
    local matches
    matches="$(echo "$all" | jq -c --arg handle "$id" \
      '[.list[] | select(.value.labels.email // "" | split("@")[0] == $handle) | .value]')"
    local count
    count="$(echo "$matches" | jq 'length')"
    if [[ "$count" -eq 0 ]]; then
      log_error "$id: not found"
      return 1
    elif [[ "$count" -gt 1 ]]; then
      log_error "$id: ambiguous ($count matches):"
      echo "$matches" | jq -r '.[] | "  \(.username) \(.labels.email // "")"' >&2
      return 1
    fi
    consumer="$(echo "$matches" | jq '.[0]')"
    fi
  fi

  if [[ -z "$consumer" || "$consumer" == "null" ]]; then
    log_error "$id: not found"
    return 1
  fi

  local oid group_id
  oid="$(echo "$consumer" | jq -r '.username')"
  group_id="$(echo "$consumer" | jq -r '.group_id // ""')"

  if [[ "$group_id" == "$target" ]]; then
    log_info "$oid: already in $target (skipped)"
    return 2
  fi

  if [[ -n "$dry_run" ]]; then
    log_info "$oid: would move ${group_id:-none} -> $target"
    return 0
  fi

  # Build PUT payload preserving existing fields
  local payload
  payload="$(echo "$consumer" | jq -c --arg grp "$target" '{
    username: .username,
    desc: (.desc // ""),
    labels: (.labels // {}),
    plugins: (.plugins // {}),
    group_id: $grp
  }')"

  local code
  code="$(apisix_put "consumers/${oid}" "$payload")"
  if [[ "$code" =~ ^2 ]]; then
    log_success "$oid: moved ${group_id:-none} -> $target"
    return 0
  else
    log_error "$oid: PUT failed (HTTP $code)"
    return 1
  fi
}

# -------------------------
# Usage / dispatch
# -------------------------
usage() {
  cat <<'EOF'
Usage: ctl consumers <subcommand>

Subcommands:
  list                 List all consumers (OID, handle, email, group, created)
  move <ids...>        Move consumers between groups
                       --to <group>     Target consumer group (required)
                       --file <path>    Load identifiers from file (one per line)
                       --dry-run        Show what would change without applying

Identifiers can be OID (UUID), email, or handle (email local part).
EOF
}

# Strip global flags before dispatch
ARGS=()
for arg in "$@"; do
  case "$arg" in --test|-t) ;; *) ARGS+=("$arg") ;; esac
done
set -- "${ARGS[@]:-}"

case "${1:-help}" in
  list) shift; cmd_list "$@" ;;
  move) shift; cmd_move "$@" ;;
  *)    usage ;;
esac
