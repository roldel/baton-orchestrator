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
TMP_DIR="$BASE_DIR/tmp/rendered" # This is where the temporary rendered file will go

echo "[render-server-conf] Starting render for project: $PROJECT"
echo "[render-server-conf] Template: $TEMPLATE"
echo "[render-server-conf] Env file: $ENV_FILE"
echo "[render-server-conf] Temporary output dir: $TMP_DIR"

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

command -v envsubst >/dev/null 2>&1 || { echo "[render-server-conf] ERROR: envsubst not found (install gettext)" >&2; exit 1; }

mkdir -p "$TMP_DIR"

# --- Load .env and export everything so envsubst can see them ---
# set -a makes all subsequent variable assignments automatically exported
set -a
# shellcheck source=/dev/null
. "$ENV_FILE"
set +a # Disable auto-exporting after .env is sourced

# --- Normalize comma-separated aliases for Nginx (space-separated is standard) ---
# Ensure DOMAIN_ALIASES is exported after normalization
DOMAIN_ALIASES="$(echo "${DOMAIN_ALIASES:-}" | tr ',' ' ' | tr -s ' ')"
export DOMAIN_ALIASES
echo "[render-server-conf] Normalized DOMAIN_ALIASES='${DOMAIN_ALIASES:-}'"


# --- Verify mandatory vars (copied from old version) ---
missing=0
# Ensure this list covers ALL variables in your `server.conf` template that need substitution
for v in DOMAIN_NAME DOCKER_NETWORK_SERVICE_ALIAS APP_PORT DOMAIN_ADMIN_EMAIL; do # Added DOMAIN_ADMIN_EMAIL based on example-project/.env.sample
  eval "val=\${$v:-}"
  if [ -z "$val" ]; then
    echo "[render-server-conf] ERROR: $v missing or empty in $ENV_FILE" >&2
    missing=1
  else
    echo "[render-server-conf] ✅ $v=$val"
  fi
done
[ "$missing" -eq 0 ] || { echo "[render-server-conf] ❌ Missing mandatory vars. Aborting." >&2; exit 1; }


# --- Define the variables envsubst should process ---
# This list MUST include every variable placeholder you have in your server.conf template
# (e.g., ${DOMAIN_NAME}, ${APP_PORT}, etc.)
# If you add new variables to server.conf, you must add them here and also export them above.
VARS_TO_SUBSTITUTE='${DOMAIN_NAME} ${DOMAIN_ALIASES} ${DOCKER_NETWORK_SERVICE_ALIAS} ${APP_PORT} ${DOMAIN_ADMIN_EMAIL} ${WEBHOOK_URL}'

TEMP_RENDER="$TMP_DIR/${DOMAIN_NAME}.conf"

echo "[render-server-conf] Substituting variables into template…"

# Perform the substitution, only for the specified variables
envsubst "$VARS_TO_SUBSTITUTE" < "$TEMPLATE" > "$TEMP_RENDER"

# --- Verify result ---
if [ ! -s "$TEMP_RENDER" ]; then
  echo "[render-server-conf] ERROR: Rendered file is empty: $TEMP_RENDER" >&2
  exit 1
fi

echo "[render-server-conf] Render complete: $TEMP_RENDER"

# Print path so deploy.sh can continue the pipeline
echo "$TEMP_RENDER"