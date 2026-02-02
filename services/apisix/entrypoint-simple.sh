#!/usr/bin/env sh
set -e

# Fix log dir permissions (volumes may be created as root)
mkdir -p /var/log/apisix/billing /var/log/apisix/wiretap
chown -R apisix:apisix /var/log/apisix /usr/local/apisix/logs
chmod 755 /var/log/apisix/billing /var/log/apisix/wiretap

# Create real log files (symlinks to /dev/stdout won't work after privilege drop)
touch /usr/local/apisix/logs/access.log /usr/local/apisix/logs/error.log
chown apisix:apisix /usr/local/apisix/logs/access.log /usr/local/apisix/logs/error.log

CONFIG="/usr/local/apisix/conf/config.yaml"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG not found"
  exit 1
fi

# Clean stale runtime files
rm -f /usr/local/apisix/logs/nginx.pid /usr/local/apisix/logs/worker_events.sock

# Start apisix as apisix user
su -s /bin/sh apisix -c "apisix init && apisix start -c '$CONFIG'"

# Forward error log to container stdout (so docker logs works)
exec tail -F /usr/local/apisix/logs/error.log
