#!/usr/bin/env sh
set -e

# Template-driven config generation with single source of truth
if [ -n "${CUSTOM_PROFILE}" ]; then
  TEMPLATE_SOURCE="/usr/local/apisix/conf/config-${CUSTOM_PROFILE}-template.yaml"

  if [ -f "$TEMPLATE_SOURCE" ]; then
    echo "Using templated profile: ${CUSTOM_PROFILE}"
    echo "Processing template: ${TEMPLATE_SOURCE}"

    # Substitute environment variables in template
    envsubst < "$TEMPLATE_SOURCE" > /usr/local/apisix/conf/config.yaml

    echo "✅ Configuration generated from template with environment variables"
  else
    echo "WARNING: Template ${TEMPLATE_SOURCE} not found, trying static fallback"
    STATIC_SOURCE="/usr/local/apisix/conf/config-${CUSTOM_PROFILE}-static.yaml"

    if [ -f "$STATIC_SOURCE" ]; then
      echo "Using static fallback: ${STATIC_SOURCE}"
      cp "$STATIC_SOURCE" /usr/local/apisix/conf/config.yaml
    else
      echo "ERROR: Neither template nor static config found for profile ${CUSTOM_PROFILE}"
      exit 1
    fi
  fi
else
  echo "No CUSTOM_PROFILE set, using default template"
  if [ -f "/usr/local/apisix/conf/config-template.yaml" ]; then
    envsubst < /usr/local/apisix/conf/config-template.yaml > /usr/local/apisix/conf/config.yaml
  else
    echo "ERROR: Default template not found"
    exit 1
  fi
fi

# Clean stale runtime files
rm -f /usr/local/apisix/logs/nginx.pid /usr/local/apisix/logs/worker_events.sock

# Start APISIX
apisix init
apisix start -c /usr/local/apisix/conf/config.yaml

# Keep container in foreground
tail -f /usr/local/apisix/logs/error.log