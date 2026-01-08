#!/usr/bin/env sh
set -e

CONFIG="/usr/local/apisix/conf/config.yaml"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG not found"
  exit 1
fi

# Clean stale runtime files
rm -f /usr/local/apisix/logs/nginx.pid /usr/local/apisix/logs/worker_events.sock

# Start APISIX with config.yaml
apisix init
apisix start -c "$CONFIG"

# Keep container in foreground
tail -f /usr/local/apisix/logs/error.log
