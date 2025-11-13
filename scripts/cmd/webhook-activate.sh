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
# shellcheck source=/dev/null
. "$ENV_FILE"

# 4. Validate the format of WEBHOOK_URL
"$VALIDATE_WEBHOOK_URL" "$WEBHOOK_URL"


# 5. BLOCKING: refuse to proceed unless site is fully live
if ! sh "$TOOLS_DIR/projects/check-site-live.sh" "$PROJECT"; then
    echo "Site not live yet → run deploy.sh first"
    exit 1
fi

echo "[webhook-activate] Site is live — proceeding"

# 6. Render server conf file
TARGET_CONF="$WEBHOOK_DIR/${DOMAIN_NAME}-webhook.conf"

if [ -f "$TARGET_CONF" ]; then
    echo "[webhook-activate] ERROR: Webhook config already exists: $TARGET_CONF"
    echo "                    Edit or remove it manually if you want to change it."
    exit 1
fi

mkdir -p "$WEBHOOK_DIR"

echo "[webhook-activate] Enabling ${DOMAIN_NAME} → ${WEBHOOK_URL}"
envsubst '$DOMAIN_NAME $WEBHOOK_URL' < "$TEMPLATE" > "$TARGET_CONF"

# 7. ATOMIC: test config — on failure, remove what we just wrote
if ! sh "$TOOLS_DIR/nginx/test-config.sh"; then
    echo "[webhook-activate] ERROR: Nginx configuration test failed after adding webhook!"
    echo "                    Removing broken config: $TARGET_CONF"
    rm -f "$TARGET_CONF"
    echo "[webhook-activate] Activation aborted — no changes applied."
    exit 1
fi

# 8. Only reload if everything is valid
sh "$TOOLS_DIR/nginx/reload.sh"

echo "[webhook-activate] Webhook successfully activated → $TARGET_CONF"
echo "[webhook-activate] Done."