#!/bin/sh
# scripts/cmd/webhook-activate.sh
# Final, bulletproof, atomic, blocking webhook activation

set -eu

[ $# -lt 1 ] && { echo "Usage: $0 <project-name>" >&2; exit 1; }

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
TOOLS_DIR="$BASE_DIR/scripts/tools"
WEBHOOK_DIR="/srv/baton-orchestrator/webhooks.d"
TEMPLATE="$TOOLS_DIR/webhook/webhook.conf"
ENV_FILE="$PROJECT_DIR/.env"

HELPERS_DIR="/opt/baton-orchestrator/scripts/tools/helpers"
VALIDATE_WEBHOOK_URL="$HELPERS_DIR/validate-webhook-url.sh"

echo "[webhook-activate] Starting webhook activation for project: $PROJECT"

# 1. Validation chain
sh "$TOOLS_DIR/projects/validate-exists.sh"   "$PROJECT"
sh "$TOOLS_DIR/projects/validate-content.sh"  "$PROJECT"

# 2. Require the three mandatory vars
sh "$TOOLS_DIR/projects/validate-env.sh" "$PROJECT" \
    DOMAIN_NAME WEBHOOK_URL PAYLOAD_SIGNATURE

# 3. Load project env
# Read in isolated subshells, not sourced directly: TOOLS_DIR, WEBHOOK_DIR,
# TEMPLATE and VALIDATE_WEBHOOK_URL are all reused below, and a project's
# own .env sourced directly could redefine any of them — e.g. pointing
# VALIDATE_WEBHOOK_URL at /bin/true to bypass the nginx-injection check on
# WEBHOOK_URL just below. envsubst is explicitly scoped to DOMAIN_NAME and
# WEBHOOK_URL only (see the envsubst call further down), so those are the
# only two values this script actually needs out of the project's .env.
# DOMAIN_NAME specifically is resolved via compute-site-key.sh rather than
# extracted raw: it's substituted unescaped into the webhook.conf template
# below AND used to build TARGET_CONF, so without compute-site-key.sh's
# path-traversal/character validation a project's own .env could redirect
# TARGET_CONF outside WEBHOOK_DIR or inject nginx directives via envsubst.
LOAD_ENV_SAFE_SH="$HELPERS_DIR/load-env-safe.sh"
DOMAIN_NAME="$(sh "$HELPERS_DIR/compute-site-key.sh" "$PROJECT")"
WEBHOOK_URL="$(
  set +eu
  . "$LOAD_ENV_SAFE_SH"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${WEBHOOK_URL:-}"
  fi
)"
export DOMAIN_NAME WEBHOOK_URL

# 4. Validate the format of WEBHOOK_URL
if [ ! -x "$VALIDATE_WEBHOOK_URL" ]; then
    echo "[webhook-activate] ERROR: validate-webhook-url script not found or not executable: $VALIDATE_WEBHOOK_URL" >&2
    exit 1
fi
sh "$VALIDATE_WEBHOOK_URL" "$WEBHOOK_URL"


# 5. BLOCKING: refuse to proceed unless site is fully live
if ! sh "$TOOLS_DIR/projects/check-site-live.sh" "$PROJECT"; then
    echo "Site not live yet → run deploy.sh first"
    exit 1
fi

echo "[webhook-activate] Site is live — proceeding"

# 6. Render outside webhooks.d. A matching snippet is a no-op, so a second
# deploy --webhook updates or succeeds instead of failing closed.
TARGET_CONF="$WEBHOOK_DIR/${DOMAIN_NAME}-webhook.conf"
mkdir -p "$WEBHOOK_DIR"
echo "[webhook-activate] Enabling ${DOMAIN_NAME} → ${WEBHOOK_URL}"
. "$TOOLS_DIR/webhook/snippet-lib.sh"
if ! baton_install_webhook_snippet \
    "$TEMPLATE" \
    "$TARGET_CONF" \
    "$TOOLS_DIR/nginx/test-config.sh" \
    "$TOOLS_DIR/nginx/reload.sh"
then
    echo "[webhook-activate] Activation aborted." >&2
    exit 1
fi

echo "[webhook-activate] Webhook successfully activated → $TARGET_CONF"
echo "[webhook-activate] Done."