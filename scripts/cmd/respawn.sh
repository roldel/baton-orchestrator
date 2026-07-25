#!/bin/sh
# scripts/cmd/respawn.sh
#
# Full Project Reset:
# 1. Detects if webhook is currently active
# 2. Stands down the project (stops containers, removes nginx config)
# 3. Deploys the project (starts containers, renders config, ensures SSL)
# 4. Reactivates webhook if it was previously active

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <project-name>" >&2
    exit 1
fi

PROJECT="$1"
BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
WEBHOOK_CONF_DIR="/srv/baton-orchestrator/webhooks.d"

# Tools
CMD_DIR="$BASE_DIR/scripts/cmd"
TOOLS_DIR="$BASE_DIR/scripts/tools"

echo "===== [respawn] Starting respawn for project: $PROJECT ====="

# 1. Validation
# We use existing tools to ensure we aren't trying to respawn a ghost
sh "$TOOLS_DIR/projects/validate-exists.sh" "$PROJECT"
sh "$TOOLS_DIR/projects/validate-content.sh" "$PROJECT"

# 2. Detect Webhook Status
# We need to know this BEFORE stand-down, because stand-down removes the webhook config.
RESTORE_WEBHOOK="no"

if [ -f "$PROJECT_DIR/.env" ]; then
    # Extract DOMAIN_NAME to check for the specific webhook config file
    # shellcheck source=/dev/null
    . "$PROJECT_DIR/.env"
    
    if [ -n "${DOMAIN_NAME:-}" ]; then
        CURRENT_WEBHOOK_CONF="$WEBHOOK_CONF_DIR/${DOMAIN_NAME}-webhook.conf"
        if [ -f "$CURRENT_WEBHOOK_CONF" ]; then
            echo "[respawn] Detected active webhook at: $CURRENT_WEBHOOK_CONF"
            RESTORE_WEBHOOK="yes"
        fi
    fi
fi

# 3. Execute Stand Down
echo "------------------------------------------------------------"
echo "[respawn] Phase 1: Standing Down"
sh "$CMD_DIR/stand-down.sh" "$PROJECT"

# 4. Execute Deploy
echo "------------------------------------------------------------"
echo "[respawn] Phase 2: Deploying"
sh "$CMD_DIR/deploy.sh" "$PROJECT"

# 5. Restore Webhook (if previously active)
if [ "$RESTORE_WEBHOOK" = "yes" ]; then
    echo "------------------------------------------------------------"
    echo "[respawn] Phase 3: Restoring Webhook"
    sh "$CMD_DIR/webhook-activate.sh" "$PROJECT"
else
    echo "[respawn] No webhook was active previously; skipping activation."
fi

echo "===== [respawn] Completed successfully for: $PROJECT ====="