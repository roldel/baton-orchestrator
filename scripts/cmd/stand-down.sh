#!/bin/sh
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via 'baton stand-down <project>'"; exit 1; }
. "$BASE_DIR/env-setup.sh"

proj="${1:-}"
[ -n "$proj" ] || { echo "Usage: baton stand-down <project>"; exit 1; }

eval "$("$SCRIPT_DIR/tools/domain-name-aliases-retriever.sh" "$PROJECTS_DIR/$proj/server.conf")"
conf="$CONF_DIR/${DOMAIN_NAME}.conf"
if [ -f "$conf" ]; then
  ts=$(date +%Y%m%d-%H%M%S)
  mv "$conf" "$conf.disabled.$ts"
  docker exec ingress-nginx nginx -s reload || true
  echo "Disabled site: $DOMAIN_NAME"
else
  echo "No live conf for $DOMAIN_NAME"
fi
