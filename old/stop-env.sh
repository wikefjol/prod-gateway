#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Function to show usage
usage() {
  cat <<EOF
Usage: ${0##*/} <environment>

Stop APISIX environment(s).

Arguments:
  environment    Which environment to stop: dev | test | both

Examples:
  ${0##*/} dev     # Stop development environment
  ${0##*/} test    # Stop test environment
  ${0##*/} both    # Stop both environments

EOF
}

# Check if argument provided
if [[ $# -eq 0 ]]; then
  echo "ERROR: Environment argument required" >&2
  echo ""
  usage
  exit 1
fi

ENVIRONMENT="$1"

# Change to project directory
cd "$PROJECT_DIR"

case "$ENVIRONMENT" in
  dev)
    echo "Stopping APISIX Development Environment..."
    docker compose -f docker-compose.dev.yml down
    echo "Development environment stopped."
    ;;
  test)
    echo "Stopping APISIX Test Environment..."
    docker compose -f docker-compose.test.yml down
    echo "Test environment stopped."
    ;;
  both)
    echo "Stopping Both APISIX Environments..."
    docker compose -f docker-compose.dev.yml down
    docker compose -f docker-compose.test.yml down
    echo "Both environments stopped."
    ;;
  *)
    echo "ERROR: Invalid environment '$ENVIRONMENT'" >&2
    echo "Expected: dev | test | both" >&2
    exit 1
    ;;
esac