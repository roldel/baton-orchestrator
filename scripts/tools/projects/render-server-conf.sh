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

# --- Load .env so envsubst can see every template variable ---
# Load into this shell. Restore the trusted paths immediately after.
_RSC_BASE_DIR="$BASE_DIR"
_RSC_PROJECT_DIR="$PROJECT_DIR"
_RSC_ENV_FILE="$ENV_FILE"
_RSC_TEMPLATE="$TEMPLATE"
_RSC_TMP_DIR="$TMP_DIR"
_RSC_PROJECT="$PROJECT"

# PATH and IFS decide which binaries run and how later loops split words.
# Linker variables decide which libraries those binaries load. Snapshot the
# pre-load values (including "unset") and put them back after the load so a
# project .env cannot replace them. load_env_safe also rejects these names.
_RSC_PATH_SET=0
if [ "${PATH+x}" = x ]; then
  _RSC_PATH_SET=1
  _RSC_PATH=$PATH
fi
_RSC_IFS_SET=0
if [ "${IFS+x}" = x ]; then
  _RSC_IFS_SET=1
  _RSC_IFS=$IFS
fi
_RSC_LD_PRELOAD_SET=0
if [ "${LD_PRELOAD+x}" = x ]; then
  _RSC_LD_PRELOAD_SET=1
  _RSC_LD_PRELOAD=$LD_PRELOAD
fi
_RSC_LD_LIBRARY_PATH_SET=0
if [ "${LD_LIBRARY_PATH+x}" = x ]; then
  _RSC_LD_LIBRARY_PATH_SET=1
  _RSC_LD_LIBRARY_PATH=$LD_LIBRARY_PATH
fi
_RSC_LD_AUDIT_SET=0
if [ "${LD_AUDIT+x}" = x ]; then
  _RSC_LD_AUDIT_SET=1
  _RSC_LD_AUDIT=$LD_AUDIT
fi
_RSC_LD_DEBUG_SET=0
if [ "${LD_DEBUG+x}" = x ]; then
  _RSC_LD_DEBUG_SET=1
  _RSC_LD_DEBUG=$LD_DEBUG
fi
unset LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT LD_DEBUG

. "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
load_env_safe "$ENV_FILE"

BASE_DIR="$_RSC_BASE_DIR"
PROJECT_DIR="$_RSC_PROJECT_DIR"
ENV_FILE="$_RSC_ENV_FILE"
TEMPLATE="$_RSC_TEMPLATE"
TMP_DIR="$_RSC_TMP_DIR"
PROJECT="$_RSC_PROJECT"
export PROJECT
if [ "$_RSC_PATH_SET" -eq 1 ]; then
  PATH="$_RSC_PATH"
  export PATH
else
  unset PATH
fi
if [ "$_RSC_IFS_SET" -eq 1 ]; then
  IFS="$_RSC_IFS"
else
  unset IFS
fi
if [ "$_RSC_LD_PRELOAD_SET" -eq 1 ]; then
  LD_PRELOAD="$_RSC_LD_PRELOAD"
  export LD_PRELOAD
else
  unset LD_PRELOAD
fi
if [ "$_RSC_LD_LIBRARY_PATH_SET" -eq 1 ]; then
  LD_LIBRARY_PATH="$_RSC_LD_LIBRARY_PATH"
  export LD_LIBRARY_PATH
else
  unset LD_LIBRARY_PATH
fi
if [ "$_RSC_LD_AUDIT_SET" -eq 1 ]; then
  LD_AUDIT="$_RSC_LD_AUDIT"
  export LD_AUDIT
else
  unset LD_AUDIT
fi
if [ "$_RSC_LD_DEBUG_SET" -eq 1 ]; then
  LD_DEBUG="$_RSC_LD_DEBUG"
  export LD_DEBUG
else
  unset LD_DEBUG
fi
unset _RSC_BASE_DIR _RSC_PROJECT_DIR _RSC_ENV_FILE _RSC_TEMPLATE _RSC_TMP_DIR _RSC_PROJECT \
  _RSC_PATH_SET _RSC_PATH _RSC_IFS_SET _RSC_IFS \
  _RSC_LD_PRELOAD_SET _RSC_LD_PRELOAD _RSC_LD_LIBRARY_PATH_SET _RSC_LD_LIBRARY_PATH \
  _RSC_LD_AUDIT_SET _RSC_LD_AUDIT _RSC_LD_DEBUG_SET _RSC_LD_DEBUG

# --- Normalize comma-separated aliases for Nginx (space-separated is standard) ---
# baton_normalize_domain_aliases splits on a fixed IFS and rejects any token
# that is not a hostname character, so a value that survived the loader cannot
# change how the words are split or inject an nginx directive.
. "$BASE_DIR/scripts/tools/helpers/check-domain-aliases.sh"
if ! DOMAIN_ALIASES="$(baton_normalize_domain_aliases "${DOMAIN_ALIASES:-}")"; then
  exit 1
fi
export DOMAIN_ALIASES
echo "[render-server-conf] Normalized DOMAIN_ALIASES='${DOMAIN_ALIASES:-}'" >&2

# WEBHOOK_URL is also in VARS_TO_SUBSTITUTE below (a server.conf template may
# reference it), so it too is substituted unescaped via envsubst — same
# nginx-injection concern as DOMAIN_ALIASES above. webhook-activate.sh already
# runs it through this same check before using it in webhook.conf; validate
# it here too, so this path isn't the odd one out. Optional: only set when a
# project actually uses the webhook feature.
if [ -n "${WEBHOOK_URL:-}" ]; then
  sh "$BASE_DIR/scripts/tools/helpers/validate-webhook-url.sh" "$WEBHOOK_URL"
fi

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

# These values are written into the shared nginx config by envsubst. Reject
# anything that is not a port, a DNS label, an email, or a project name.
. "$BASE_DIR/scripts/tools/helpers/nginx-allowlists.sh"
if ! baton_check_project_name "$PROJECT"; then
  echo "[render-server-conf] ERROR: PROJECT '$PROJECT' is not a valid project name" >&2
  exit 1
fi
if ! baton_check_admin_email "${DOMAIN_ADMIN_EMAIL:-}"; then
  echo "[render-server-conf] ERROR: DOMAIN_ADMIN_EMAIL contains characters outside the allowed set" >&2
  exit 1
fi
if [ "$STATIC_SITE" != "yes" ]; then
  if ! baton_check_app_port "$APP_PORT"; then
    echo "[render-server-conf] ERROR: APP_PORT must be an integer from 1 to 65535" >&2
    exit 1
  fi
  if ! baton_check_service_alias "$DOCKER_NETWORK_SERVICE_ALIAS"; then
    echo "[render-server-conf] ERROR: DOCKER_NETWORK_SERVICE_ALIAS must be a DNS label (letters, digits, '_' or '-', not starting with '-')" >&2
    exit 1
  fi
fi

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