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

# DOMAIN_NAME drives WEBHOOK_CONF below, which this script `rm -f`s, so it's
# resolved via compute-site-key.sh (not extracted raw) for its path-
# traversal/character validation — a project's own .env setting DOMAIN_NAME
# to a path-traversal value must not let this script delete an arbitrary
# host file. compute-site-key.sh loads .env via load_env_safe, never
# sourced directly, so TOOLS_DIR (reused below) can't be clobbered either.
DOMAIN_NAME="$(sh "$BASE_DIR/scripts/tools/helpers/compute-site-key.sh" "$PROJECT")"

WEBHOOK_CONF="/srv/baton-orchestrator/webhooks.d/${DOMAIN_NAME}-webhook.conf"

if [ ! -f "$WEBHOOK_CONF" ]; then
    echo "[webhook-deactivate] No webhook active for $DOMAIN_NAME (missing $WEBHOOK_CONF)"
    echo "[webhook-deactivate] Nothing to do."
    exit 0
fi

echo "[webhook-deactivate] Removing $WEBHOOK_CONF"

# Optional: keep a timestamped backup (same pattern as install-server-conf.sh)
# Restore below uses this exact path, not a glob: a glob matching more than
# one leftover backup from earlier runs would make `cp` fail (destination
# treated as a missing directory) and silently no-op under `|| true`.
mkdir -p "$BASE_DIR/tmp/webhook-backups"
BACKUP_FILE="$BASE_DIR/tmp/webhook-backups/${DOMAIN_NAME}-webhook.conf.$(date +%Y%m%d-%H%M%S)"
cp "$WEBHOOK_CONF" "$BACKUP_FILE"

rm -f "$WEBHOOK_CONF"

# Test nginx config before reloading
if ! sh "$TOOLS_DIR/nginx/test-config.sh"; then
    echo "[webhook-deactivate] ERROR: Nginx config broken after removal!" >&2
    echo "[webhook-deactivate] Restoring backup..." >&2
    cp "$BACKUP_FILE" "$WEBHOOK_CONF" 2>/dev/null || true
    exit 1
fi

# Reload nginx
sh "$TOOLS_DIR/nginx/reload.sh"

echo "[webhook-deactivate] Webhook deactivated and nginx reloaded successfully"
echo "[webhook-deactivate] Removed: $WEBHOOK_CONF"