#!/bin/sh
# scripts/tools/webhook/auto-redeploy.sh
# ------------------------------------------------------------
# Consumes a .baton task file created by the webhook service.
# Expected variables inside the file:
#   REPO_LOCATION                (mandatory)
#   DOCKER_COMPOSE_RESTART_REQUIRED = YES|NO
#   CI_PIPELINE_LOCATION         (optional)
#   CUSTOM_REDEPLOY_SCRIPT_LOCATION (optional)
# ------------------------------------------------------------
set -eu

TASK_FILE="${1:-}"
[ -n "$TASK_FILE" ] || { echo "Usage: $0 <task-file>" >&2; exit 1; }
[ -f "$TASK_FILE" ]  || { echo "ERROR: task file not found: $TASK_FILE" >&2; exit 1; }

# ------------------------------------------------------------------
# Load the task file (key=value lines)
# ------------------------------------------------------------------
# shellcheck disable=SC1090
. "$TASK_FILE"

# ------------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------------
log() { printf '[auto-redeploy] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

# ------------------------------------------------------------------
# Mandatory variables
# ------------------------------------------------------------------
REPO_LOCATION="${REPO_LOCATION:-}"
[ -n "$REPO_LOCATION" ] || die "REPO_LOCATION missing in $TASK_FILE"
[ -d "$REPO_LOCATION" ] || die "REPO_LOCATION not a directory: $REPO_LOCATION"

DOCKER_COMPOSE_RESTART_REQUIRED="${DOCKER_COMPOSE_RESTART_REQUIRED:-NO}"
CI_PIPELINE_LOCATION="${CI_PIPELINE_LOCATION:-}"
CUSTOM_REDEPLOY_SCRIPT_LOCATION="${CUSTOM_REDEPLOY_SCRIPT_LOCATION:-}"

# ------------------------------------------------------------------
# 1. Custom script (if any) – short-circuit everything else
# ------------------------------------------------------------------
if [ -n "$CUSTOM_REDEPLOY_SCRIPT_LOCATION" ]; then
    [ -x "$CUSTOM_REDEPLOY_SCRIPT_LOCATION" ] || die "CUSTOM_REDEPLOY_SCRIPT_LOCATION not executable: $CUSTOM_REDEPLOY_SCRIPT_LOCATION"
    log "Executing custom redeploy script: $CUSTOM_REDEPLOY_SCRIPT_LOCATION"
    exec "$CUSTOM_REDEPLOY_SCRIPT_LOCATION" "$TASK_FILE"
    # exec replaces the shell – script must exit with proper code
fi

# ------------------------------------------------------------------
# 2. Backup current repo (temporary directory)
# ------------------------------------------------------------------
BACKUP_DIR=$(mktemp -d "/tmp/baton-backup.XXXXXX")
trap 'rm -rf "$BACKUP_DIR"' EXIT
log "Backing up current repo to $BACKUP_DIR"
cp -a "$REPO_LOCATION/." "$BACKUP_DIR/"

# ------------------------------------------------------------------
# 3. Git pull
# ------------------------------------------------------------------
log "Pulling latest changes in $REPO_LOCATION"
(
    cd "$REPO_LOCATION"
    git fetch --all --prune
    git reset --hard FETCH_HEAD
    git clean -fdx
) || die "git pull failed – restoring backup"
log "git pull succeeded"

# ------------------------------------------------------------------
# 4. Optional CI pipeline
# ------------------------------------------------------------------
if [ -n "$CI_PIPELINE_LOCATION" ]; then
    [ -x "$CI_PIPELINE_LOCATION" ] || die "CI_PIPELINE_LOCATION not executable: $CI_PIPELINE_LOCATION"
    log "Running CI pipeline: $CI_PIPELINE_LOCATION"
    if "$CI_PIPELINE_LOCATION"; then
        log "CI pipeline PASSED"
    else
        log "CI pipeline FAILED – restoring backup"
        rm -rf "$REPO_LOCATION/*" "$REPO_LOCATION/.*" 2>/dev/null || true
        cp -a "$BACKUP_DIR/." "$REPO_LOCATION/"
        die "CI pipeline failed – repo restored to previous state"
    fi
fi

# ------------------------------------------------------------------
# 5. Docker-Compose restart (if requested)
# ------------------------------------------------------------------
if [ "$DOCKER_COMPOSE_RESTART_REQUIRED" = "YES" ]; then
    COMPOSE_FILE="$REPO_LOCATION/docker-compose.yml"
    [ -f "$COMPOSE_FILE" ] || die "docker-compose.yml not found in $REPO_LOCATION"

    log "Stopping existing containers"
    docker compose -f "$COMPOSE_FILE" down || true

    log "Starting containers (build + force-recreate)"
    docker compose -f "$COMPOSE_FILE" up --build --force-recreate -d
    log "Docker-Compose restart complete"
fi

log "Redeployment finished successfully"
exit 0