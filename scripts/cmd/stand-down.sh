#!/bin/sh
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via 'baton stand-down <project>'"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

proj="${1:-}"
[ -n "$proj" ] || { echo "Usage: baton stand-down <project>"; exit 1; }

proj_dir="$PROJECTS_DIR/$proj"
env_file="$proj_dir/.env"
conf_dir="$CONF_DIR"

# Ensure project + files exist
[ -d "$proj_dir" ] || { echo "ERROR: Project directory not found: $proj_dir" >&2; exit 1; }
[ -f "$proj_dir/server.conf" ] || { echo "ERROR: Missing server.conf in $proj_dir" >&2; exit 1; }
[ -f "$env_file" ] || { echo "ERROR: Missing .env in $proj_dir (see .env.sample)" >&2; exit 1; }

# Load env to get DOMAIN_NAME
load_dotenv "$env_file"

conf="$conf_dir/${DOMAIN_NAME}.conf"
if [ -f "$conf" ]; then
  ts=$(date +%Y%m%d-%H%M%S)
  mv "$conf" "$conf.disabled.$ts"
  docker exec ingress-nginx nginx -s reload || true
  echo "Disabled site: $DOMAIN_NAME"
else
  echo "No live conf for $DOMAIN_NAME"
fi
