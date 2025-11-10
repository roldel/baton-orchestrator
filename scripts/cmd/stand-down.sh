#!/bin/sh
# Stand down a project: remove its nginx config, reload nginx, and stop its Docker Compose stack.
# SSL certificates are NOT removed.
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

# 1) Basic Project Existence Check (lighter than full project-validator for this context)
if [ ! -d "$PROJ_DIR" ]; then
  echo "ERROR: Project directory not found: $PROJ_DIR" >&2
  exit 1
fi

# Find compose file
COMPOSE_FILE=""
if [ -f "$PROJ_DIR/docker-compose.yml" ]; then
  COMPOSE_FILE="$PROJ_DIR/docker-compose.yml"
elif [ -f "$PROJ_DIR/template-docker-compose.yml" ]; then
  COMPOSE_FILE="$PROJ_DIR/template-docker-compose.yml"
fi

if [ -z "$COMPOSE_FILE" ]; then
  echo "ERROR: No docker-compose file found for project $PROJECT in $PROJ_DIR" >&2
  exit 1
fi

# 2) Remove project's Nginx configuration file
if [ -f "$NGINX_CONF_FILE" ]; then
  echo "[stand-down] Removing Nginx configuration file: $NGINX_CONF_FILE"
  rm -f "$NGINX_CONF_FILE"
else
  echo "[stand-down] Nginx configuration file not found for $PROJECT (already removed or never deployed): $NGINX_CONF_FILE"
fi

# 3) Reload Nginx to apply changes
# Use the existing tool script for robustness
echo "[stand-down] Reloading Nginx to stop serving project $PROJECT..."
"$SCRIPT_DIR/tools/nginx/server-reload.sh"

# 4) Spool down the project's Docker Compose stack
echo "[stand-down] Stopping Docker Compose stack for project: $PROJECT"
docker compose -f "$COMPOSE_FILE" down || {
  echo "WARNING: Failed to stop Docker Compose for project $PROJECT. It might not have been running." >&2
  true # Continue script execution even if down fails (e.g., if containers weren't up)
}
echo "[stand-down] Docker Compose stack for $PROJECT stopped."


echo "[stand-down] Completed stand-down for project: $PROJECT"
echo "[stand-down] Note: SSL certificates for $PROJECT remain on the system."