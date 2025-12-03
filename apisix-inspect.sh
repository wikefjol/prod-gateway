#!/usr/bin/env bash
set -Eeuo pipefail

########################################
# Config & defaults
########################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APISIX_CONFIG_DIR="${APISIX_CONFIG_DIR:-$HOME/.config/apisix}"

# Detail level: summary | compact | full
DETAIL_LEVEL="compact"

# Environment selection: dev | test | (empty for default)
ENVIRONMENT=""

# Short codes → resource names
# r = routes, s = services, u = upstreams, c = consumers,
# g = consumer_groups, a = global_rules, t = ssls (TLS), m = stream_routes
declare -A CODE_TO_RESOURCE=(
  [r]="routes"
  [s]="services"
  [u]="upstreams"
  [c]="consumers"
  [g]="consumer_groups"
  [a]="global_rules"
  [t]="ssls"
  [m]="stream_routes"
)

# Resource labels for headers
declare -A RESOURCE_LABEL=(
  [routes]="ROUTES"
  [services]="SERVICES"
  [upstreams]="UPSTREAMS"
  [consumers]="CONSUMERS"
  [consumer_groups]="CONSUMER GROUPS"
  [global_rules]="GLOBAL RULES"
  [ssls]="SSL CERTIFICATES"
  [stream_routes]="STREAM ROUTES"
)

# For name-based selectors (routes,services,...)
declare -A NAME_TO_CODE=(
  [routes]="r"
  [services]="s"
  [upstreams]="u"
  [consumers]="c"
  [consumer_groups]="g"
  [global_rules]="a"
  [ssls]="t"
  [stream_routes]="m"
)

# Default: all resources
ALL_CODES=(r s u c g a t m)

INCLUDE_CODES=()
EXCLUDE_CODES=()

########################################
# Helpers
########################################

usage() {
  cat <<EOF
Usage: ${0##*/} [-i codes] [-x codes] [-l level] [-e env] [--key <viewer-key>]

Quick APISIX Admin overview tool (read-only).

Options:
  -i, --include  Comma-separated short codes or names of resources to include.
                 If omitted, all are included by default.
                 Codes:
                   r = routes
                   s = services
                   u = upstreams
                   c = consumers
                   g = consumer_groups
                   a = global_rules
                   t = ssls (TLS)
                   m = stream_routes

                 Examples:
                   ${0##*/} -i r,u,c
                   ${0##*/} -i routes,upstreams

  -x, --exclude  Comma-separated codes/names to exclude.
                 Examples:
                   ${0##*/} -x t
                   ${0##*/} -x ssls,stream_routes

  -l, --level    Detail level: summary | compact | full
                 summary = just counts
                 compact = counts + key fields (default)
                 full    = raw JSON

  -e, --env      Environment to inspect: dev | test
                 If specified, loads environment-specific configuration
                 (dev: .env.dev, test: .env.test)

  -k, --key      Explicit viewer key (NOT recommended for regular use;
                 appears in shell history). Mostly for quick testing.

  -h, --help     Show this help

Environment / config resolution:

  APISIX_ADMIN_API   Admin API base URL.
                     Precedence:
                       1) APISIX_ADMIN_API in environment
                       2) ADMIN_API in env/config
                       3) Values from:
                            - $SCRIPT_DIR/.env
                            - $APISIX_CONFIG_DIR/admin.env
                       4) Default: http://localhost:9180/apisix/admin

  VIEWER_KEY         Admin API viewer key.
                     Precedence:
                       1) VIEWER_KEY from:
                            - environment
                            - -k/--key flag
                       2) VIEWER_KEY_FILE -> read file contents
                       3) Values from:
                            - $SCRIPT_DIR/.env
                            - $APISIX_CONFIG_DIR/admin.env
                       4) Otherwise: script exits with an error.

  VIEWER_KEY_FILE    Path to a file containing the viewer key (no quotes, one
                     key only). Used only if VIEWER_KEY is not already set.

  APISIX_CONFIG_DIR  Base directory for per-user config (default: $APISIX_CONFIG_DIR).
                     Expected file:
                       \$APISIX_CONFIG_DIR/admin.env

Examples:
  ${0##*/}                     # compact overview of everything (default env)
  ${0##*/} -e dev              # compact overview of dev environment
  ${0##*/} -e test -l summary  # only counts for test environment
  ${0##*/} -e dev -i r,u -l full # full JSON for routes + upstreams in dev
  ${0##*/} -x t,m              # everything except SSLs and stream routes

EOF
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed. Please install jq." >&2
    exit 1
  fi
}

section_header() {
  local label=$1
  echo
  echo "=============================="
  echo "$label"
  echo "=============================="
}

# Parse selector list like "r,u,c" or "routes,upstreams"
parse_selector_list() {
  local raw="$1"
  local -n out_array_ref="$2"  # nameref to output array

  IFS=',' read -ra parts <<<"$raw"
  for p in "${parts[@]}"; do
    # trim spaces and lowercase
    local x
    x=$(echo "$p" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    [[ -z "$x" ]] && continue

    # Direct code match (r,s,u,...)
    if [[ -n "${CODE_TO_RESOURCE[$x]:-}" ]]; then
      out_array_ref+=("$x")
      continue
    fi

    # Name match (routes,services,...)
    if [[ -n "${NAME_TO_CODE[$x]:-}" ]]; then
      out_array_ref+=("${NAME_TO_CODE[$x]}")
      continue
    fi

    echo "WARNING: unknown selector '$p' ignored." >&2
  done
}

# Deduplicate an array of codes
dedupe_codes() {
  local -a input=("$@")
  local -A seen=()
  local out=()
  local code
  for code in "${input[@]}"; do
    if [[ -z "${seen[$code]:-}" ]]; then
      seen["$code"]=1
      out+=("$code")
    fi
  done
  echo "${out[@]}"
}

# Compute final list of codes based on include/exclude
compute_selected_codes() {
  local selected=()

  if ((${#INCLUDE_CODES[@]} > 0)); then
    # Start from include list
    selected=("${INCLUDE_CODES[@]}")
  else
    # Start from "all"
    selected=("${ALL_CODES[@]}")
  fi

  if ((${#EXCLUDE_CODES[@]} > 0)); then
    local -A exclude_map=()
    local code
    for code in "${EXCLUDE_CODES[@]}"; do
      exclude_map["$code"]=1
    done

    local filtered=()
    for code in "${selected[@]}"; do
      if [[ -z "${exclude_map[$code]:-}" ]]; then
        filtered+=("$code")
      fi
    done
    selected=("${filtered[@]}")
  fi

  # Deduplicate in case of weird overlaps
  read -ra selected <<<"$(dedupe_codes "${selected[@]}")"
  echo "${selected[@]}"
}

curl_json() {
  local resource="$1"
  curl -sS "${APISIX_ADMIN_API}/${resource}" \
    -H "X-API-KEY: ${VIEWER_KEY}"
}

print_summary() {
  local label="$1"
  local resource="$2"
  local json="$3"

  section_header "$label"
  echo "--- GET ${resource}"
  echo "$json" | jq -r --arg label "$label" '
    if has("total") then
      $label + ": " + (.total|tostring)
    elif has("list") then
      $label + ": " + ((.list|length)|tostring)
    elif has("error_msg") then
      $label + ": ERROR - " + .error_msg
    else
      $label + ": (unexpected response shape)"
    end
  '
}

print_compact_routes() {
  local json="$1"
  echo "$json" | jq -r '
    "count: \(.total // (.list|length // 0))",
    ( .list[]?.value? |
      "- id=\(.id // "<no-id>") uri=\(.uri // "<no-uri>") name=\(.name // "")"
    )
  '
}

print_compact_services() {
  local json="$1"
  echo "$json" | jq -r '
    "count: \(.total // (.list|length // 0))",
    ( .list[]? |
      "- id=\(.id // "<no-id>") name=\(.name // "")"
    )
  '
}

print_compact_upstreams() {
  local json="$1"
  echo "$json" | jq -r '
    "count: \(.total // (.list|length // 0))",
    ( .list[]?.value? |
      "- id=\(.id // "<no-id>") name=\(.name // "") type=\(.type // "")"
    )
  '
}

print_compact_consumers() {
  local json="$1"
  echo "$json" | jq -r '
    "count: \(.total // (.list|length // 0))",
    ( .list[]?.value? |
      "- username=\(.username // "<no-username>") desc=\(.desc // "")"
    )
  '
}


print_compact_generic_list() {
  local json="$1"
  echo "$json" | jq -r '
    "count: \(.total // (.list|length // 0))",
    ( .list[]? |
      "- id=\(.id // "<no-id>") name=\(.name // "")"
    )
  '
}

print_compact_ssls() {
  local json="$1"
  echo "$json" | jq -r '
    "count: \(.total // (.list|length // 0))",
    ( .list[]? |
      "- id=\(.id // "<no-id>") snis=\((.snis // []) | join(","))"
    )
  '
}

print_compact_stream_routes() {
  local json="$1"
  # If stream mode disabled, just show the error
  echo "$json" | jq -r '
    if has("error_msg") then
      "ERROR: " + .error_msg
    else
      "count: \(.total // (.list|length // 0))",
      ( .list[]? |
        "- id=\(.id // "<no-id>")"
      )
    end
  '
}

print_compact() {
  local label="$1"
  local resource="$2"
  local json="$3"

  section_header "$label"
  echo "--- GET ${resource}"

  case "$resource" in
    routes)          print_compact_routes "$json" ;;
    services)        print_compact_services "$json" ;;
    upstreams)       print_compact_upstreams "$json" ;;
    consumers)       print_compact_consumers "$json" ;;
    consumer_groups) print_compact_generic_list "$json" ;;
    global_rules)    print_compact_generic_list "$json" ;;
    ssls)            print_compact_ssls "$json" ;;
    stream_routes)   print_compact_stream_routes "$json" ;;
    *)               print_compact_generic_list "$json" ;;
  esac
}

print_full() {
  local label="$1"
  local resource="$2"
  local json="$3"

  section_header "$label"
  echo "--- GET ${resource}"
  echo "$json" | jq .
}

print_resource() {
  local resource="$1"
  local label="${RESOURCE_LABEL[$resource]:-$resource}"

  # Fetch JSON
  local json
  if ! json=$(curl_json "$resource"); then
    section_header "$label"
    echo "--- GET ${resource}"
    echo "ERROR: failed to fetch resource (curl error)" >&2
    return
  fi

  case "$DETAIL_LEVEL" in
    summary) print_summary "$label" "$resource" "$json" ;;
    compact) print_compact "$label" "$resource" "$json" ;;
    full)    print_full    "$label" "$resource" "$json" ;;
    *)       print_compact "$label" "$resource" "$json" ;;
  esac
}

########################################
# Config initialisation
########################################

init_config() {
  # Capture any existing env / CLI overrides so config files don't clobber them
  local had_env_admin_api=0 had_env_viewer=0
  local env_admin_api="" env_viewer=""

  if [[ -n "${APISIX_ADMIN_API+x}" ]]; then
    had_env_admin_api=1
    env_admin_api="${APISIX_ADMIN_API-}"
  fi
  if [[ -n "${VIEWER_KEY+x}" ]]; then
    had_env_viewer=1
    env_viewer="${VIEWER_KEY-}"
  fi

  # Source config files in order:
  #   1) Project-local .env (shared defaults)
  #   2) Environment-specific .env file (if environment specified)
  #   3) Per-user admin.env (~/.config/apisix/admin.env)
  local config_files=()
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    config_files+=("$SCRIPT_DIR/.env")
  fi
  if [[ -n "$ENVIRONMENT" && -f "$SCRIPT_DIR/.env.$ENVIRONMENT" ]]; then
    config_files+=("$SCRIPT_DIR/.env.$ENVIRONMENT")
  fi
  if [[ -f "${APISIX_CONFIG_DIR}/admin.env" ]]; then
    config_files+=("${APISIX_CONFIG_DIR}/admin.env")
  fi

  for f in "${config_files[@]}"; do
    # shellcheck disable=SC1090
    source "$f"
  done

  # Restore explicit env / CLI values if they existed before sourcing
  if (( had_env_admin_api )); then
    APISIX_ADMIN_API="$env_admin_api"
  fi
  if (( had_env_viewer )); then
    VIEWER_KEY="$env_viewer"
  fi

  # If APISIX_ADMIN_API still unset, prefer ADMIN_API from config/env, else default
  if [[ -z "${APISIX_ADMIN_API:-}" ]]; then
    if [[ -n "${ADMIN_API:-}" ]]; then
      APISIX_ADMIN_API="$ADMIN_API"
    else
      APISIX_ADMIN_API="http://localhost:9180/apisix/admin"
    fi
  fi

  # If VIEWER_KEY still unset, but VIEWER_KEY_FILE is set, read from file
  if [[ -z "${VIEWER_KEY:-}" ]]; then
    if [[ -n "${VIEWER_KEY_FILE:-}" && -f "$VIEWER_KEY_FILE" ]]; then
      VIEWER_KEY="$(<"$VIEWER_KEY_FILE")"
    fi
  fi

  if [[ -z "${VIEWER_KEY:-}" ]]; then
    cat >&2 <<EOF
ERROR: VIEWER_KEY not set.

Tried:
  - VIEWER_KEY from environment or -k/--key
  - VIEWER_KEY_FILE (if set)
  - $SCRIPT_DIR/.env
  - ${APISIX_CONFIG_DIR}/admin.env

Recommended setup for per-user config:

  mkdir -p "${APISIX_CONFIG_DIR}"
  chmod 700 "${APISIX_CONFIG_DIR}"
  cat > "${APISIX_CONFIG_DIR}/admin.env" <<'END'
APISIX_ADMIN_API="http://localhost:9180/apisix/admin"
VIEWER_KEY="your-viewer-key-here"
# ADMIN_KEY="your-admin-key-here"  # if needed elsewhere
END
  chmod 600 "${APISIX_CONFIG_DIR}/admin.env"

Then rerun: ${0##*/}

EOF
    exit 1
  fi
}

########################################
# Main
########################################

require_jq

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--include)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: -i/--include requires an argument" >&2; exit 1; }
      parse_selector_list "$1" INCLUDE_CODES
      shift
      ;;
    -x|--exclude)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: -x/--exclude requires an argument" >&2; exit 1; }
      parse_selector_list "$1" EXCLUDE_CODES
      shift
      ;;
    -l|--level)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: -l/--level requires an argument" >&2; exit 1; }
      case "$1" in
        summary|compact|full)
          DETAIL_LEVEL="$1"
          ;;
        *)
          echo "ERROR: invalid level '$1' (expected summary|compact|full)" >&2
          exit 1
          ;;
      esac
      shift
      ;;
    -e|--env)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: -e/--env requires an argument" >&2; exit 1; }
      case "$1" in
        dev|test)
          ENVIRONMENT="$1"
          ;;
        *)
          echo "ERROR: invalid environment '$1' (expected dev|test)" >&2
          exit 1
          ;;
      esac
      shift
      ;;
    -k|--key)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: -k/--key requires an argument" >&2; exit 1; }
      VIEWER_KEY="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option '$1'" >&2
      echo
      usage
      exit 1
      ;;
  esac
done

# Initialise config (APISIX_ADMIN_API, VIEWER_KEY, etc.)
init_config

# Quick connectivity + auth check
check_status=$(curl -sS -o /dev/null -w '%{http_code}' \
  "${APISIX_ADMIN_API}/routes" \
  -H "X-API-KEY: ${VIEWER_KEY}" || echo "000")

case "$check_status" in
  200)
    # all good
    ;;
  401|403)
    echo "ERROR: Unauthorized (${check_status}) when calling ${APISIX_ADMIN_API}/routes" >&2
    echo "       Check that VIEWER_KEY matches a configured 'viewer' admin_key in APISIX." >&2
    exit 1
    ;;
  000)
    echo "ERROR: Could not reach APISIX Admin API at ${APISIX_ADMIN_API} (network error)." >&2
    echo "       Is APISIX running? Is the URL correct?" >&2
    exit 1
    ;;
  *)
    echo "ERROR: Unexpected HTTP ${check_status} from ${APISIX_ADMIN_API}/routes" >&2
    exit 1
    ;;
esac

# Decide what to fetch
read -ra SELECTED_CODES <<<"$(compute_selected_codes)"

if ((${#SELECTED_CODES[@]} == 0)); then
  echo "Nothing to do: empty include/exclude result." >&2
  exit 0
fi

for code in "${SELECTED_CODES[@]}"; do
  resource="${CODE_TO_RESOURCE[$code]}"
  print_resource "$resource"
done

echo
echo "[DONE] APISIX overview (${DETAIL_LEVEL}) complete."
echo
