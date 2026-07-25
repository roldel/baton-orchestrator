#!/bin/sh
# Render a project's server.conf using envsubst.
# Output file name = ${SITE_KEY}.conf (SITE_KEY = $DOMAIN_NAME)

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <project-name>" >&2
    exit 1
fi

PROJECT="$1"
export PROJECT

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"
TEMPLATE="$PROJECT_DIR/server.conf"
TMP_DIR="$BASE_DIR/tmp/rendered" # This is where the temporary rendered file will go

# Progress/diagnostic output goes to stderr; stdout is reserved for the single
# final line (the rendered file path) that callers capture via $(...).
echo "[render-server-conf] Starting render for project: $PROJECT" >&2
echo "[render-server-conf] Template: $TEMPLATE" >&2
echo "[render-server-conf] Env file: $ENV_FILE" >&2
echo "[render-server-conf] Temporary output dir: $TMP_DIR" >&2

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
echo "[render-server-conf] Normalized DOMAIN_ALIASES='${DOMAIN_ALIASES:-}'" >&2

# --- Static-site flag + SITE_KEY (SITE_KEY = $DOMAIN_NAME, namespaces the
# conf.d filename and shared-files dir per project) ---
STATIC_SITE="${STATIC_SITE:-no}"
SITE_KEY="$(sh "$BASE_DIR/scripts/tools/helpers/compute-site-key.sh" "$PROJECT")"
export SITE_KEY
echo "[render-server-conf] Static site: $STATIC_SITE (SITE_KEY=$SITE_KEY)" >&2

# --- Verify mandatory vars ---
# Ensure this list covers ALL variables in your `server.conf` template that need substitution.
# Domain vars are always required; the static flag decides whether the app-proxy
# vars are needed too.
MANDATORY_VARS="PROJECT DOMAIN_NAME DOMAIN_ADMIN_EMAIL"
if [ "$STATIC_SITE" != "yes" ]; then
  MANDATORY_VARS="$MANDATORY_VARS DOCKER_NETWORK_SERVICE_ALIAS APP_PORT"
fi

missing=0
for v in $MANDATORY_VARS; do
  eval "val=\${$v:-}"
  if [ -z "$val" ]; then
    echo "[render-server-conf] ERROR: $v missing or empty in $ENV_FILE" >&2
    missing=1
  else
    echo "[render-server-conf] ✅ $v=$val" >&2
  fi
done
[ "$missing" -eq 0 ] || { echo "[render-server-conf] ❌ Missing mandatory vars. Aborting." >&2; exit 1; }


# --- Define the variables envsubst should process ---
# This list MUST include every variable placeholder you have in your server.conf template
# (e.g., ${DOMAIN_NAME}, ${APP_PORT}, etc.)
# If you add new variables to server.conf, you must add them here and also export them above.
# Built additively from the static flag.
VARS_TO_SUBSTITUTE='${PROJECT} ${SITE_KEY} ${DOMAIN_NAME} ${DOMAIN_ALIASES} ${DOMAIN_ADMIN_EMAIL} ${WEBHOOK_URL}'
if [ "$STATIC_SITE" != "yes" ]; then
  VARS_TO_SUBSTITUTE="$VARS_TO_SUBSTITUTE "'${DOCKER_NETWORK_SERVICE_ALIAS} ${APP_PORT}'
fi

TEMP_RENDER="$TMP_DIR/${SITE_KEY}.conf"

echo "[render-server-conf] Substituting variables into template…" >&2

# Perform the substitution, only for the specified variables
envsubst "$VARS_TO_SUBSTITUTE" < "$TEMPLATE" > "$TEMP_RENDER"

# --- Verify result ---
if [ ! -s "$TEMP_RENDER" ]; then
  echo "[render-server-conf] ERROR: Rendered file is empty: $TEMP_RENDER" >&2
  exit 1
fi

# --- Guard against un-substituted placeholders ---
# envsubst is deliberately scoped to an explicit variable list (so nginx's own
# $host/$uri/etc. survive). The side effect is that any ${VAR} in the template
# NOT in that list is left as a literal ${VAR}, which nginx then rejects. Catch
# that here with a clear message instead of failing later in `nginx -t`.
# nginx templates only use the ${...} brace form for envsubst vars, so a
# leftover ${WORD} is unambiguously an un-substituted placeholder.
LEFTOVER="$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$TEMP_RENDER" | sort -u | tr '\n' ' ' || true)"
if [ -n "$LEFTOVER" ]; then
  echo "[render-server-conf] ERROR: un-substituted placeholder(s) in rendered config: $LEFTOVER" >&2
  echo "[render-server-conf]        Add each variable to MANDATORY_VARS and VARS_TO_SUBSTITUTE (and set it in .env)." >&2
  exit 1
fi

echo "[render-server-conf] Render complete: $TEMP_RENDER" >&2

# Print path so deploy.sh can continue the pipeline
echo "$TEMP_RENDER"