#!/bin/sh
# Stand down a project: remove its nginx config, reload nginx, and stop its Docker Compose stack.
# SSL certificates are NOT removed.
# Only docker-compose.yml is supported (template-docker-compose.yml is deprecated).
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

# Resolve BASE_DIR then load shared env
THIS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "$THIS_DIR/../.." && pwd)"
export BASE_DIR
# shellcheck disable=SC1091
. "$BASE_DIR/env-setup.sh"

echo "[stand-down] Initiating stand-down for project: $PROJECT"
echo "[stand-down] BASE_DIR=$BASE_DIR"

PROJ_DIR="$PROJECTS_DIR/$PROJECT"
NGINX_CONF_FILE="$ORCHESTRATOR_DIR/nginx/conf.d/$PROJECT.conf"

# 1) Basic Project Existence Check
if [ ! -d "$PROJ_DIR" ]; then
  echo "ERROR: Project directory not found: $PROJ_DIR" >&2
  exit 1
fi

# 2) Find docker-compose.yml (ONLY — template-docker-compose.yml is no longer used)
COMPOSE_FILE=""
if [ -f "$PROJ_DIR/docker-compose.yml" ]; then
  COMPOSE_FILE="$PROJ_DIR/docker-compose.yml"
  echo "[stand-down] Found compose file: $COMPOSE_FILE"
else
  echo "WARNING: No docker-compose.yml found in $PROJ_DIR" >&2
  echo "[stand-down] Skipping container shutdown (none defined)." >&2
fi

# 3) Remove project's Nginx configuration file
if [ -f "$NGINX_CONF_FILE" ]; then
  echo "[stand-down] Removing Nginx configuration file: $NGINX_CONF_FILE"
  rm -f "$NGINX_CONF_FILE"
else
  echo "[stand-down] Nginx configuration file not found (already removed or never deployed): $NGINX_CONF_FILE"
fi

# 4) Reload Nginx to apply changes
echo "[stand-down] Reloading Nginx to stop serving project $PROJECT..."
"$SCRIPT_DIR/tools/nginx/server-reload.sh"

# 5) Stop Docker Compose stack (only if compose file exists)
if [ -n "$COMPOSE_FILE" ]; then
  echo "[stand-down] Stopping Docker Compose stack for project: $PROJECT"
  docker compose -f "$COMPOSE_FILE" down || {
    echo "WARNING: 'docker compose down' failed for $PROJECT — likely already stopped or not running." >&2
  }
  echo "[stand-down] Docker Compose stack stopped (or was never up)."
else
  echo "[stand-down] No docker-compose.yml → skipping container shutdown."
fi

# 6) Final status
echo "[stand-down] Completed stand-down for project: $PROJECT"
echo "[stand-down] Note: SSL certificates for $PROJECT remain on the system."