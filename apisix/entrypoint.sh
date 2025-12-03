#!/usr/bin/env sh
set -e

# 1) Generate config.yaml from template using envsubst
# Support APISIX_PROFILE for environment-specific configs
if [ -n "${APISIX_PROFILE}" ]; then
  CONFIG_TEMPLATE="/usr/local/apisix/conf/config-${APISIX_PROFILE}.yaml"
  CONFIG_OUTPUT="/usr/local/apisix/conf/config.yaml"

  if [ -f "$CONFIG_TEMPLATE" ]; then
    echo "Generating APISIX config from profile template: ${CONFIG_TEMPLATE}..."
    echo "DEBUG: ETCD_HOST=${ETCD_HOST}, ADMIN_KEY=${ADMIN_KEY}, VIEWER_KEY=${VIEWER_KEY}"
    envsubst < "$CONFIG_TEMPLATE" > "$CONFIG_OUTPUT"
  else
    echo "WARNING: Profile template ${CONFIG_TEMPLATE} not found, falling back to config-template.yaml"
    if [ -f /usr/local/apisix/conf/config-template.yaml ]; then
      envsubst < /usr/local/apisix/conf/config-template.yaml > "$CONFIG_OUTPUT"
    fi
  fi
elif [ -f /usr/local/apisix/conf/config-template.yaml ]; then
  echo "Generating APISIX config from template..."
  envsubst < /usr/local/apisix/conf/config-template.yaml \
    > /usr/local/apisix/conf/config.yaml
fi

# 2) Wait for etcd to be reachable
# Use environment-specific etcd host if available
ETCD_HOST_CHECK="${ETCD_HOST_CHECK:-etcd:2379}"
if [ -n "${APISIX_PROFILE}" ]; then
  case "${APISIX_PROFILE}" in
    "dev")
      ETCD_HOST_CHECK="etcd-dev:2379"
      ;;
    "test")
      ETCD_HOST_CHECK="etcd-test:2379"
      ;;
  esac
fi

# Parse host and port for connection check
ETCD_CHECK_HOST=$(echo "$ETCD_HOST_CHECK" | cut -d':' -f1)
ETCD_CHECK_PORT=$(echo "$ETCD_HOST_CHECK" | cut -d':' -f2)

echo "Waiting for etcd (tcp) at ${ETCD_HOST_CHECK} ..."
# Skip the TCP check for now and proceed directly
echo "etcd port check skipped, proceeding with APISIX startup..."

# 3) Clean stale runtime files from previous failed starts
rm -f /usr/local/apisix/logs/nginx.pid /usr/local/apisix/logs/worker_events.sock

# 4) Start APISIX
apisix init
apisix start -c /usr/local/apisix/conf/config.yaml

# 5) Keep container in foreground
tail -f /usr/local/apisix/logs/error.log
