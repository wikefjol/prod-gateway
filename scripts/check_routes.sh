#!/bin/bash
set -euo pipefail

# default env
ENV="${1:-dev}"

ENV_FILE="infra/env/.env.${ENV}"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Env file not found: $ENV_FILE" >&2
  exit 1
fi

# Load env vars (ADMIN_KEY etc)
# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${ADMIN_KEY:-}" ]; then
  echo "❌ ADMIN_KEY not set in $ENV_FILE" >&2
  exit 1
fi

curl -i "http://127.0.0.1:9180/apisix/admin/routes" \
  -H "X-API-KEY: $ADMIN_KEY"