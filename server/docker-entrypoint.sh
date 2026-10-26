#!/bin/sh
# Bind mounts keep the owner they have on the host, often root. Hand the data
# directory to the app user, then drop root.
set -e
if [ "$(id -u)" = 0 ]; then
  mkdir -p "$CONFIG_DIR"
  chown -R app:app "$CONFIG_DIR"
  exec su-exec app /app/entrypoint.sh "$@"
fi
exec /app/entrypoint.sh "$@"
