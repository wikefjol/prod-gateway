#!/usr/bin/env sh
set -e

# Simple profile-based config selection
if [ -n "${CUSTOM_PROFILE}" ]; then
  CONFIG_SOURCE="/usr/local/apisix/conf/config-${CUSTOM_PROFILE}-static.yaml"

  if [ -f "$CONFIG_SOURCE" ]; then
    echo "Using custom profile: ${CUSTOM_PROFILE}"
    echo "Copying config from: ${CONFIG_SOURCE}"
    cp "$CONFIG_SOURCE" /usr/local/apisix/conf/config.yaml
  else
    echo "WARNING: Profile config ${CONFIG_SOURCE} not found, using default"
    cp /usr/local/apisix/conf/config-template.yaml /usr/local/apisix/conf/config.yaml
  fi
else
  echo "No CUSTOM_PROFILE set, using config-template.yaml"
  cp /usr/local/apisix/conf/config-template.yaml /usr/local/apisix/conf/config.yaml
fi

# Clean stale runtime files
rm -f /usr/local/apisix/logs/nginx.pid /usr/local/apisix/logs/worker_events.sock

# Start APISIX
apisix init
apisix start -c /usr/local/apisix/conf/config.yaml

# Keep container in foreground
tail -f /usr/local/apisix/logs/error.log