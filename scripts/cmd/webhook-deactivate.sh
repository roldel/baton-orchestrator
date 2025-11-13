#!/bin/sh
# scripts/cmd/webhook-deactivate.sh
# Safely removes a project's webhook nginx snippet and reloads nginx

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <project-name>" >&2
    exit 1
fi

PROJECT="$1"
BASE_DIR="/opt/baton-orchestrator"
TOOLS_DIR="$BASE_DIR/scripts/tools"

echo "[webhook-deactivate] Deactivating webhook for project: $PROJECT"

# Reuse existing validation tools
sh "$TOOLS_DIR/projects/validate-exists.sh" "$PROJECT"
sh "$TOOLS_DIR/projects/validate-env.sh"    "$PROJECT" DOMAIN_NAME

# Load DOMAIN_NAME from project's .env
# shellcheck source=/dev/null
. "/srv/projects/$PROJECT/.env"

WEBHOOK_CONF="/srv/baton-orchestrator/webhooks.d/${DOMAIN_NAME}-webhook.conf"

if [ ! -f "$WEBHOOK_CONF" ]; then
    echo "[webhook-deactivate] No webhook active for $DOMAIN_NAME (missing $WEBHOOK_CONF)"
    echo "[webhook-deactivate] Nothing to do."
    exit 0
fi

echo "[webhook-deactivate] Removing $WEBHOOK_CONF"

# Optional: keep a timestamped backup (same pattern as install-server-conf.sh)
mkdir -p "$BASE_DIR/tmp/webhook-backups"
cp "$WEBHOOK_CONF" "$BASE_DIR/tmp/webhook-backups/${DOMAIN_NAME}-webhook.conf.$(date +%Y%m%d-%H%M%S)"

rm -f "$WEBHOOK_CONF"

# Test nginx config before reloading
if ! sh "$TOOLS_DIR/nginx/test-config.sh"; then
    echo "[webhook-deactivate] ERROR: Nginx config broken after removal!" >&2
    echo "[webhook-deactivate] Restoring backup..." >&2
    cp "$BASE_DIR/tmp/webhook-backups/${DOMAIN_NAME}-webhook.conf."* "$WEBHOOK_CONF" 2>/dev/null || true
    exit 1
fi

# Reload nginx
sh "$TOOLS_DIR/nginx/reload.sh"

echo "[webhook-deactivate] Webhook deactivated and nginx reloaded successfully"
echo "[webhook-deactivate] Removed: $WEBHOOK_CONF"