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
    # Extract DOMAIN_NAME via an isolated subshell using load_env_safe, not
    # sourced directly (see that file's header): CMD_DIR is reused below
    # (stand-down.sh/deploy.sh/webhook-activate.sh all get `sh`'d through
    # it), and a project's own .env sourced directly could redirect those
    # calls to an attacker-controlled script, on top of being able to
    # execute arbitrary commands immediately just by being sourced at all.
    DOMAIN_NAME="$(
        set +eu
        . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
        if load_env_safe "$PROJECT_DIR/.env"; then
            printf '%s' "${DOMAIN_NAME:-}"
        fi
    )"

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
if ! sh "$CMD_DIR/stand-down.sh" "$PROJECT"; then
    echo "[respawn] ERROR: stand-down failed for '$PROJECT' — aborting before deploy" >&2
    echo "[respawn]        to avoid deploying on top of a partial teardown." >&2
    exit 1
fi

# 4. Execute Deploy
echo "------------------------------------------------------------"
echo "[respawn] Phase 2: Deploying"
sh "$CMD_DIR/deploy.sh" "$PROJECT"

# 5. Restore Webhook (if previously active)
if [ "$RESTORE_WEBHOOK" = "yes" ]; then
    echo "------------------------------------------------------------"
    echo "[respawn] Phase 3: Restoring Webhook"
    # stand-down.sh tolerates a webhook-deactivate.sh failure (warns and
    # continues) rather than aborting the teardown, so the webhook may never
    # actually have been removed. webhook-activate.sh hard-fails if its
    # target config already exists, so check first instead of letting a
    # tolerated warning above turn into a hard respawn failure here.
    if [ -f "$CURRENT_WEBHOOK_CONF" ]; then
        echo "[respawn] Webhook config already present at $CURRENT_WEBHOOK_CONF — it was never deactivated, nothing to restore."
    else
        sh "$CMD_DIR/webhook-activate.sh" "$PROJECT"
    fi
else
    echo "[respawn] No webhook was active previously; skipping activation."
fi

echo "===== [respawn] Completed successfully for: $PROJECT ====="