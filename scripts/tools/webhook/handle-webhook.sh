#!/bin/sh
# scripts/tools/webhook/handle-webhook.sh
# Simple, reliable webhook task processor
# Processes one task_*.baton file → git pull + optional restart

set -eu

TASK_FILE="$1"
LOG="/var/log/baton-webhook.log"
BACKUP_DIR="/srv/tmp"

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$@" | tee -a "$LOG"
}

fail() {
    log "ERROR: $*"
    mv "$TASK_FILE" "$TASK_FILE.failed"
    exit 1
}

[ -f "$TASK_FILE" ] || fail "Task file not found: $TASK_FILE"

log "Processing task: $TASK_FILE"

# Load task variables (safe sourcing)
# shellcheck source=/dev/null
. "$TASK_FILE"

# Required
PROJECT="${PROJECT:-}"
REPO_LOCATION="${REPO_LOCATION:-}"
[ -n "$PROJECT" ]       || fail "Missing PROJECT in task"
[ -n "$REPO_LOCATION" ] || fail "Missing REPO_LOCATION in task"

log "Project: $PROJECT → $REPO_LOCATION"

# Optional defaults
TARGET_BRANCH="${TARGET_BRANCH:-main}"
DOCKER_COMPOSE_RESTART_REQUIRED="${DOCKER_COMPOSE_RESTART_REQUIRED:-NO}"

# Early exit: custom redeploy script
if [ -n "${CUSTOM_REDEPLOY_SCRIPT_LOCATION:-}" ] && [ -f "$CUSTOM_REDEPLOY_SCRIPT_LOCATION" ]; then
    log "Running custom redeploy script: $CUSTOM_REDEPLOY_SCRIPT_LOCATION"
    if sh "$CUSTOM_REDEPLOY_SCRIPT_LOCATION" >>"$LOG" 2>&1; then
        log "Custom script succeeded"
        rm -f "$TASK_FILE"
        exit 0
    else
        log "Custom script FAILED"
        mv "$TASK_FILE" "$TASK_FILE.custom-failed"
        exit 1
    fi
fi

# Backup current repo state
mkdir -p "$BACKUP_DIR"
BACKUP="$(mktemp -d "$BACKUP_DIR/baton-backup.XXXXXX")"
log "Backing up repo to $BACKUP"
cp -a "$REPO_LOCATION/." "$BACKUP/" || fail "Failed to create backup"

# Git: fetch + hard reset to origin/TARGET_BRANCH
log "Updating repo: git fetch + reset --hard origin/$TARGET_BRANCH"
cd "$REPO_LOCATION"

git fetch --all --prune || fail "git fetch failed → restored backup"
git checkout "$TARGET_BRANCH" 2>/dev/null || git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH" || fail "checkout failed"
git reset --hard "origin/$TARGET_BRANCH" || fail "git reset --hard failed → restored backup"
git clean -fd || log "Warning: git clean failed (non-fatal)"

# Success: remove backup
rm -rf "$BACKUP"
log "Git update completed successfully"

# Optional: CI pipeline
if [ -n "${CI_PIPELINE_LOCATION:-}" ] && [ -f "$CI_PIPELINE_LOCATION" ]; then
    log "Running CI pipeline: $CI_PIPELINE_LOCATION"
    if sh "$CI_PIPELINE_LOCATION" >>"$LOG" 2>&1; then
        log "CI pipeline succeeded"
    else
        log "CI pipeline FAILED (code kept, task marked)"
        mv "$TASK_FILE" "$TASK_FILE.ci-failed"
        exit 1
    fi
fi

# Optional: docker compose restart
if [ "$DOCKER_COMPOSE_RESTART_REQUIRED" = "YES" ]; then
    COMPOSE_FILE="$REPO_LOCATION/docker-compose.yml"
    if [ ! -f "$COMPOSE_FILE" ]; then
        log "WARNING: Restart requested but no docker-compose.yml found → skipping"
    else
        log "Restarting containers with docker-compose"
        cd "$(dirname "$COMPOSE_FILE")"
        docker compose down || log "Warning: docker compose down failed"
        docker compose up -d --build --force-recreate >>"$LOG" 2>&1 || {
            log "ERROR: docker compose up failed"
            mv "$TASK_FILE" "$TASK_FILE.docker-failed"
            exit 1
        }
        log "Containers restarted successfully"
    fi
fi

# All done
log "Task completed successfully for $PROJECT"
rm -f "$TASK_FILE"
exit 0