#!/bin/sh
# Usage: ./scripts/manual/render-server-conf.sh <project-name>
# Renders projects/<project>/server.conf by substituting env vars from projects/<project>/.env
# Output: temp/<project>.conf (repo root)

set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

TEMPLATE="projects/$PROJECT/server.conf"
ENV_FILE="projects/$PROJECT/.env"
OUT_DIR="orchestrator/server-confs"
OUT_FILE="$OUT_DIR/$PROJECT.conf"

echo "[render-server-conf] Project: $PROJECT"
echo "[render-server-conf] Template: $TEMPLATE"
echo "[render-server-conf] Env file: $ENV_FILE"
echo "[render-server-conf] Output:   $OUT_FILE"

# --- basic checks ---
[ -r "$TEMPLATE" ] || { echo "ERROR: missing or unreadable $TEMPLATE" >&2; exit 1; }
[ -r "$ENV_FILE" ]  || { echo "ERROR: missing or unreadable $ENV_FILE" >&2; exit 1; }
command -v envsubst >/dev/null 2>&1 || { echo "ERROR: envsubst not found (install gettext)" >&2; exit 1; }

# --- load .env and export everything so envsubst can see them ---
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# --- normalize comma-separated aliases for Caddy ---
DOMAIN_ALIASES="$(echo "${DOMAIN_ALIASES:-}" | tr ',' ' ')"
export DOMAIN_ALIASES
echo "[render-server-conf] Normalized DOMAIN_ALIASES='${DOMAIN_ALIASES:-}'"

# --- verify mandatory vars ---
missing=0
for v in DOMAIN_NAME DOCKER_NETWORK_SERVICE_ALIAS APP_PORT; do
  eval "val=\${$v:-}"
  if [ -z "$val" ]; then
    echo "ERROR: $v missing or empty in $ENV_FILE" >&2
    missing=1
  else
    echo "[render-server-conf] ✅ $v=$val"
  fi
done
[ "$missing" -eq 0 ] || { echo "[render-server-conf] ❌ Missing mandatory vars"; exit 1; }

# --- prepare output dir ---
mkdir -p "$OUT_DIR"

# --- substitute variables into template ---
VARS='${DOMAIN_NAME} ${DOCKER_NETWORK_SERVICE_ALIAS} ${APP_PORT} ${DOMAIN_ALIASES} ${DOMAIN_ADMIN_EMAIL}'
echo "[render-server-conf] Substituting variables into template…"
envsubst "$VARS" < "$TEMPLATE" > "$OUT_FILE"

# --- verify result ---
if [ ! -s "$OUT_FILE" ]; then
  echo "ERROR: Rendered file is empty: $OUT_FILE" >&2
  exit 1
fi

echo "[render-server-conf] 🎉 Render complete: $OUT_FILE"