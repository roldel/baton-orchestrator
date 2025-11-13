# /opt/baton-orchestrator/scripts/tools/webhook/handle_webhook.sh
#!/bin/sh
set -eu

TASK_FILE="$1"
LOG="/var/log/baton-webhook.log"
LOCK="/tmp/baton-handle.lock"
BACKUP=""

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG"
}

# --- lock ---
while [ -f "$LOCK" ]; do sleep 1; done
touch "$LOCK"

cleanup() {
    # remove lock
    rm -f "$LOCK"
    # remove backup dir if it was created
    if [ -n "${BACKUP:-}" ] && [ -d "$BACKUP" ]; then
        rm -rf "$BACKUP"
    fi
}
trap 'cleanup' EXIT

log "Processing $TASK_FILE"

# --- load task ---
. "$TASK_FILE"

# --- custom script? ---
if [ -n "${CUSTOM_REDEPLOY_SCRIPT_LOCATION:-}" ]; then
    log "Running custom script: $CUSTOM_REDEPLOY_SCRIPT_LOCATION"
    sh "$CUSTOM_REDEPLOY_SCRIPT_LOCATION" >>"$LOG" 2>&1 && log "Custom OK" || { log "Custom FAILED"; exit 1; }
    exit 0
fi

# --- backup (Fix #1) ---
# Copy the *contents* of the repo (including dotfiles) to avoid nesting and to include hidden files.
BACKUP="$(mktemp -d /tmp/baton-backup.XXXXXX)"
log "Backup → $BACKUP"
cp -a "$REPO_LOCATION/." "$BACKUP/" || { log "Backup failed"; exit 1; }

# --- git pull (fetch+hard reset as before) ---
log "git pull in $REPO_LOCATION"
(
    cd "$REPO_LOCATION"
    git fetch --all
    git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)
) >>"$LOG" 2>&1 || { 
    log "git FAILED → restoring"
    # Restore contents including dotfiles (Fix #1 restore side)
    cp -a "$BACKUP/." "$REPO_LOCATION/" 
    exit 1
}

# --- CI pipeline ---
if [ -n "${CI_PIPELINE_LOCATION:-}" ]; then
    log "Running CI: $CI_PIPELINE_LOCATION"
    sh "$CI_PIPELINE_LOCATION" >>"$LOG" 2>&1 || { 
        log "CI FAILED → restoring"
        # Restore contents including dotfiles (Fix #1 restore side)
        cp -a "$BACKUP/." "$REPO_LOCATION/"
        exit 1
    }
fi

# --- docker compose ---
if [ "${DOCKER_COMPOSE_RESTART_REQUIRED:-NO}" = "YES" ]; then
    COMPOSE="$REPO_LOCATION/docker-compose.yml"
    if [ -f "$COMPOSE" ]; then
        log "Restarting Docker Compose"
        docker compose -f "$COMPOSE" down >>"$LOG" 2>&1
        docker compose -f "$COMPOSE" up -d --build --force-recreate >>"$LOG" 2>&1
    fi
fi

# --- cleanup ---
rm -rf "$BACKUP"
rm -f "$TASK_FILE"
log "Redeploy SUCCESS"
