#!/bin/sh
# Install the rendered server config for a project into nginx/conf.d
# Source:  /opt/baton-orchestrator/tmp/rendered/${DOMAIN_NAME}.conf
# Target:  /opt/baton-orchestrator/orchestrator/nginx/conf.d/${DOMAIN_NAME}.conf

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"
TMP_DIR="$BASE_DIR/tmp/rendered"
NGINX_CONF_DIR="$BASE_DIR/orchestrator/nginx/conf.d"
BACKUP_DIR="$BASE_DIR/tmp/nginx-backups"

echo "[install-server-conf] Installing server config for project: $PROJECT (dir: $PROJECT_DIR)"

# --- Basic validation ---
if [ ! -d "$PROJECT_DIR" ]; then
  echo "[install-server-conf] ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "[install-server-conf] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

# --- Load env vars to get DOMAIN_NAME ---
# shellcheck source=/dev/null
. "$ENV_FILE"

if [ -z "${DOMAIN_NAME:-}" ]; then
  echo "[install-server-conf] ERROR: DOMAIN_NAME must be set in .env" >&2
  exit 1
fi

SRC="$TMP_DIR/${DOMAIN_NAME}.conf"
DEST="$NGINX_CONF_DIR/${DOMAIN_NAME}.conf"

if [ ! -f "$SRC" ]; then
  echo "[install-server-conf] ERROR: Rendered config not found: $SRC" >&2
  echo "  Did you run render-server-conf.sh first?" >&2
  exit 1
fi

mkdir -p "$NGINX_CONF_DIR"
mkdir -p "$BACKUP_DIR"

# --- Optional: backup existing dest if present ---
if [ -f "$DEST" ]; then
  TS="$(date '+%Y%m%d-%H%M%S')"
  BACKUP_FILE="$BACKUP_DIR/${DOMAIN_NAME}.conf.$TS"
  echo "[install-server-conf] Backing up existing config: $DEST → $BACKUP_FILE"
  cp -f "$DEST" "$BACKUP_FILE"
fi

echo "[install-server-conf] Installing $SRC → $DEST"
cp -f "$SRC" "$DEST"

echo "[install-server-conf] Installation complete: $DEST"

# Print the final path (for logs / tooling if needed)
echo "$DEST"
