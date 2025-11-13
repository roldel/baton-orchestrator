#!/bin/sh
# Stand down a project:
# - Validate project exists
# - Stop its containers
# - Remove its nginx server config
# - Test nginx config
# - Reload nginx

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
TOOLS_DIR="$BASE_DIR/scripts/tools"

COMPOSE_HELPER="$TOOLS_DIR/helpers/detect-compose-file.sh"
NGINX_TEST="$TOOLS_DIR/nginx/test-config.sh"
NGINX_RELOAD="$TOOLS_DIR/nginx/reload.sh"

ENV_FILE="$PROJECT_DIR/.env"
NGINX_CONF_DIR="$BASE_DIR/orchestrator/nginx/conf.d"
BACKUP_DIR="$BASE_DIR/tmp/nginx-backups"

echo "[stand-down] Standing down project: $PROJECT"
echo "[stand-down] Project dir: $PROJECT_DIR"

# 1) Validate project directory exists
sh "$TOOLS_DIR/projects/validate-exists.sh" "$PROJECT"

# 2) Remove webhook
sh "$BASE_DIR/scripts/cmd/webhook-deactivate.sh" "$PROJECT"

# 3) Stop project containers
if [ ! -x "$COMPOSE_HELPER" ]; then
  echo "[stand-down] ERROR: detect-compose-file helper not found or not executable: $COMPOSE_HELPER" >&2
  exit 1
fi

COMPOSE_FILE="$(sh "$COMPOSE_HELPER" "$PROJECT_DIR")"
COMPOSE_DIR="$(dirname "$COMPOSE_FILE")"

echo "[stand-down] Using compose file: $COMPOSE_FILE"

cd "$COMPOSE_DIR"
echo "[stand-down] docker compose down"
docker compose -f "$COMPOSE_FILE" down || {
  echo "[stand-down] WARNING: docker compose down failed (containers may already be stopped)." >&2
}

# 4) Remove nginx server config for this domain
if [ ! -f "$ENV_FILE" ]; then
  echo "[stand-down] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$ENV_FILE"

if [ -z "${DOMAIN_NAME:-}" ]; then
  echo "[stand-down] ERROR: DOMAIN_NAME must be set in .env" >&2
  exit 1
fi

CONF_FILE="$NGINX_CONF_DIR/${DOMAIN_NAME}.conf"
mkdir -p "$BACKUP_DIR"

if [ -f "$CONF_FILE" ]; then
  TS="$(date '+%Y%m%d-%H%M%S')"
  BACKUP_FILE="$BACKUP_DIR/${DOMAIN_NAME}.conf.removed.$TS"
  echo "[stand-down] Moving nginx config: $CONF_FILE → $BACKUP_FILE"
  mv "$CONF_FILE" "$BACKUP_FILE"
else
  echo "[stand-down] No nginx server config found for domain: $CONF_FILE (nothing to remove)"
fi

# 5) Test nginx config
sh "$NGINX_TEST"

# 6) Reload nginx
sh "$NGINX_RELOAD"

echo "[stand-down] Project '$PROJECT' has been stood down:"
echo "             - Containers stopped"
echo "             - Nginx server config removed"
echo "             - Nginx reloaded"
