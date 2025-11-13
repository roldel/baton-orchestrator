#!/bin/sh
# Render a project's server.conf using envsubst.
# Output file name = ${DOMAIN_NAME}.conf

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <project-name>" >&2
    exit 1
fi

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"
TEMPLATE="$PROJECT_DIR/server.conf"
TMP_DIR="$BASE_DIR/tmp/rendered"
OUTPUT_DIR="$BASE_DIR/orchestrator/nginx/conf.d"

# --- Sanity checks ---
if [ ! -d "$PROJECT_DIR" ]; then
    echo "[render-server-conf] ERROR: Project directory not found: $PROJECT_DIR" >&2
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "[render-server-conf] ERROR: Missing .env file: $ENV_FILE" >&2
    exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
    echo "[render-server-conf] ERROR: Missing server.conf template: $TEMPLATE" >&2
    exit 1
fi

mkdir -p "$TMP_DIR"

# --- Load environment variables for envsubst ---
# shellcheck source=/dev/null
. "$ENV_FILE"

if [ -z "${DOMAIN_NAME:-}" ]; then
    echo "[render-server-conf] ERROR: DOMAIN_NAME must be set in .env" >&2
    exit 1
fi

# NORMALIZE DOMAIN_ALIASES: convert commas to spaces
if [ -n "${DOMAIN_ALIASES:-}" ]; then
    DOMAIN_ALIASES_NORMALIZED=$(printf '%s\n' "$DOMAIN_ALIASES" | tr ',' ' ' | tr -s ' ')
    export DOMAIN_ALIASES="$DOMAIN_ALIASES_NORMALIZED"
    echo "[render-server-conf] Normalized DOMAIN_ALIASES: '$DOMAIN_ALIASES'"
fi

TEMP_RENDER="$TMP_DIR/${DOMAIN_NAME}.conf"

echo "[render-server-conf] Rendering server.conf → $TEMP_RENDER"

envsubst < "$TEMPLATE" > "$TEMP_RENDER"

echo "[render-server-conf] Render complete."

# Print path so deploy.sh can continue the pipeline
echo "$TEMP_RENDER"
