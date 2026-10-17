#!/bin/sh
# handle-webhook.sh — safe, atomic, auditable

set -eu

TASK_FILE="$1"
LOG="/var/log/baton-webhook.log"
BACKUP=""
PROCESSED_DIR="/srv/webhooks/processed"
BASE_DIR="/opt/baton-orchestrator"
BATON_PROJECTS_ROOT="${BATON_PROJECTS_ROOT:-/srv/projects}"
BATON_REPOS_ROOT="${BATON_REPOS_ROOT:-/srv/repos}"
BATON_CI_ROOT="${BATON_CI_ROOT:-/srv/ci}"
BATON_SCRIPTS_ROOT="${BATON_SCRIPTS_ROOT:-/srv/scripts}"

. "$BASE_DIR/scripts/tools/webhook/task-lib.sh"
. "$BASE_DIR/scripts/tools/static/publish-lib.sh"
. "$BASE_DIR/scripts/tools/webhook/lock-lib.sh"

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG"
}

# One flock covers this worker and stand-down, deploy, and respawn.
baton_hold_webhook_lock "$@"

cleanup() {
    if [ -n "${BACKUP:-}" ] && [ -d "$BACKUP" ]; then
        rm -rf "$BACKUP"
    fi
}
trap 'cleanup' EXIT

# Full replace, not overlay: clears every entry (including dotfiles) under
# REPO_LOCATION before copying the backup back, so files introduced by the
# failed deploy (e.g. a new migration script) don't survive a "restore".
restore_backup() {
    log "Restoring $REPO_LOCATION from backup"
    find "$REPO_LOCATION" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "$BACKUP/." "$REPO_LOCATION/"
}

log "Processing $TASK_FILE"

# --- Ensure processed dir ---
mkdir -p "$PROCESSED_DIR"

# --- Safely load task variables ---
if ! baton_load_task_file "$TASK_FILE"; then
    log "ERROR: rejected task file $TASK_FILE"
    exit 1
fi
log "Loaded task for project ${PROJECT:-}"

[ -n "${PROJECT:-}" ] || { log "ERROR: PROJECT is not set in $TASK_FILE"; exit 1; }
[ -n "${REPO_LOCATION:-}" ] || { log "ERROR: REPO_LOCATION is not set in $TASK_FILE"; exit 1; }
if ! REPO_LOCATION=$(baton_repo_allowed "$PROJECT" "$REPO_LOCATION"); then
    log "ERROR: REPO_LOCATION is outside the allowed roots"
    exit 1
fi
export REPO_LOCATION

if [ -n "${CUSTOM_REDEPLOY_SCRIPT_LOCATION:-}" ]; then
    if ! CUSTOM_REDEPLOY_SCRIPT_LOCATION=$(baton_script_allowed "$CUSTOM_REDEPLOY_SCRIPT_LOCATION" "$REPO_LOCATION"); then
        log "ERROR: custom redeploy script is outside the allowed roots or is not an executable file"
        exit 1
    fi
    export CUSTOM_REDEPLOY_SCRIPT_LOCATION
fi

if [ -n "${CI_PIPELINE_LOCATION:-}" ]; then
    if ! CI_PIPELINE_LOCATION=$(baton_script_allowed "$CI_PIPELINE_LOCATION" "$REPO_LOCATION"); then
        log "ERROR: CI pipeline script is outside the allowed roots or is not an executable file"
        exit 1
    fi
    export CI_PIPELINE_LOCATION
fi


# --- Custom script ---
if [ -n "${CUSTOM_REDEPLOY_SCRIPT_LOCATION:-}" ]; then
    log "Running custom script: $CUSTOM_REDEPLOY_SCRIPT_LOCATION"
    if baton_run_as_webhook_user "$CUSTOM_REDEPLOY_SCRIPT_LOCATION" "$REPO_LOCATION" >>"$LOG" 2>&1; then
        log "Custom OK"
        mv "$TASK_FILE" "$PROCESSED_DIR/$(basename "$TASK_FILE").$(date +%s)" 2>/dev/null || true
        exit 0
    else
        log "Custom FAILED (code $?)"
        # No restoration needed here as custom script handles its own context
        mv "$TASK_FILE" "$PROCESSED_DIR/$(basename "$TASK_FILE").failed.$(date +%s)" 2>/dev/null || true
        exit 1
    fi
fi

# --- Backup ---
BACKUP="$(mktemp -d /tmp/baton-backup.XXXXXX)"
log "Backup → $BACKUP"
cp -a "$REPO_LOCATION/." "$BACKUP/" || { log "Backup failed"; exit 1; }

# --- Git pull ---
# Deploy the branch the webhook validated (TARGET_BRANCH), NOT whatever branch
# the on-disk checkout happens to point at. checkout -B forces the local branch
# to origin/<branch> and switches to it, so a checkout left on the wrong branch
# (or in detached HEAD) still ends up on the intended ref.
DEPLOY_BRANCH="${TARGET_BRANCH:-main}"
log "git deploy of branch '$DEPLOY_BRANCH' in $REPO_LOCATION"
# origin/ prefix keeps the revision from being parsed as an option. Trailing
# -- ends the command; this git treats a -- placed before the revision as a path.
if (
    cd "$REPO_LOCATION"
    baton_git "$REPO_LOCATION" fetch --all --prune --
    baton_git "$REPO_LOCATION" checkout -B "$DEPLOY_BRANCH" "origin/$DEPLOY_BRANCH" --
    baton_git "$REPO_LOCATION" reset --hard "origin/$DEPLOY_BRANCH" --
) >>"$LOG" 2>&1; then
    log "git pull OK"
else
    log "git FAILED → restoring"
    restore_backup
    mv "$TASK_FILE" "$PROCESSED_DIR/$(basename "$TASK_FILE").failed.$(date +%s)" 2>/dev/null || true
    exit 1
fi

# --- CI pipeline ---
if [ -n "${CI_PIPELINE_LOCATION:-}" ]; then
    log "Running CI: $CI_PIPELINE_LOCATION"
    if baton_run_as_webhook_user "$CI_PIPELINE_LOCATION" "$REPO_LOCATION" >>"$LOG" 2>&1; then
        log "CI OK"
    else
        log "CI FAILED → restoring"
        restore_backup
        mv "$TASK_FILE" "$PROCESSED_DIR/$(basename "$TASK_FILE").failed.$(date +%s)" 2>/dev/null || true
        exit 1
    fi
fi

# --- Static file publish ---
# Read STATIC_SITE and STATIC_SOURCE_DIR from the project's own .env, in an
# isolated subshell so it can't clobber already-loaded task-file vars (e.g.
# REPO_LOCATION, which some projects' .env also defines). `set +eu` inside the
# subshell keeps a malformed .env from aborting this whole script via set -eu
# (this subshell's -eu is local to it; the parent script's -eu is unaffected).
# A static project always publishes. A dynamic project publishes only when
# STATIC_SOURCE_DIR is set, and still restarts Compose below. CI, when set,
# has already run, so a build script can fill that directory first.
PROJECT_ENV="/srv/projects/${PROJECT:-}/.env"
# Clear first so a value already loaded from the task file cannot leak in.
STATIC_SITE=""
STATIC_SOURCE_DIR=""
if [ -n "${PROJECT:-}" ] && [ -f "$PROJECT_ENV" ]; then
    STATIC_SITE="$(
        set +eu
        . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
        if load_env_safe "$PROJECT_ENV"; then
            printf '%s' "${STATIC_SITE:-no}"
        fi
    )"
    [ -n "$STATIC_SITE" ] || STATIC_SITE="no"
    STATIC_SOURCE_DIR="$(
        set +eu
        . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
        if load_env_safe "$PROJECT_ENV"; then
            printf '%s' "${STATIC_SOURCE_DIR:-}"
        fi
    )"
fi

# Capture the release currently live (if any) *before* publishing, so that if
# Docker Compose fails to come back up below, the frontend can be reverted
# alongside the backend instead of leaving a new frontend paired with a
# rolled-back old backend.
PREV_STATIC_RELEASE=""
STATIC_SITE_LINK=""
if [ "$STATIC_SITE" = "yes" ] || [ -n "$STATIC_SOURCE_DIR" ]; then
    if SITE_KEY="$(sh "$BASE_DIR/scripts/tools/helpers/compute-site-key.sh" "$PROJECT" 2>>"$LOG")"; then
        STATIC_SITE_LINK="/srv/shared-files/$SITE_KEY/site"
        PREV_STATIC_RELEASE="$(readlink "$STATIC_SITE_LINK" 2>/dev/null || true)"
    fi

    log "Publishing static files: $PROJECT"
    if sh "$BASE_DIR/scripts/tools/static/sync-static-site.sh" "$PROJECT" >>"$LOG" 2>&1; then
        log "Static publish OK"
    else
        log "Static publish FAILED → restoring"
        restore_backup
        mv "$TASK_FILE" "$PROCESSED_DIR/$(basename "$TASK_FILE").failed.$(date +%s)" 2>/dev/null || true
        exit 1
    fi
fi

# Revert the static release published above back to what was live before this
# deploy. Used when Compose fails to come back up, so the rolled-back backend
# is never left paired with the new (unreleased) frontend.
revert_static_publish() {
    if [ -n "$PREV_STATIC_RELEASE" ] && [ -d "$PREV_STATIC_RELEASE" ] && [ -n "$STATIC_SITE_LINK" ]; then
        baton_atomic_symlink "$PREV_STATIC_RELEASE" "$STATIC_SITE_LINK"
        log "Reverted static files to previous release: $PREV_STATIC_RELEASE"
    fi
}

# --- Docker Compose ---
# Normalize case before comparing: STATIC_SITE elsewhere in the same .env uses
# lowercase yes/no, so accept that convention here too instead of requiring
# an exact "YES".
DOCKER_COMPOSE_RESTART_REQUIRED_NORM="$(printf '%s' "${DOCKER_COMPOSE_RESTART_REQUIRED:-NO}" | tr '[:lower:]' '[:upper:]')"
if [ "$DOCKER_COMPOSE_RESTART_REQUIRED_NORM" = "YES" ]; then
    # Resolve compose file(s) the same way as deploy/restart-containers
    # (auto-detect or DOCKER_COMPOSE_FILES from the project's .env). After
    # git pull the tree may have updated the compose layout — re-resolve now.
    COMPOSE_CMD="$BASE_DIR/scripts/tools/helpers/compose-cmd.sh"
    RESOLVE_HELPER="$BASE_DIR/scripts/tools/helpers/resolve-compose-files.sh"
    if sh "$RESOLVE_HELPER" "$REPO_LOCATION" >>"$LOG" 2>&1; then
        log "Restarting Docker Compose (down and up)"
        sh "$COMPOSE_CMD" "$REPO_LOCATION" down >>"$LOG" 2>&1 || true
        if sh "$COMPOSE_CMD" "$REPO_LOCATION" up -d --build --force-recreate >>"$LOG" 2>&1; then
            log "Docker Compose UP OK"
            # proxy_pass hostnames are resolved when nginx loads config. A
            # recreated container keeps the old address until reload. Do not
            # roll the containers back if reload fails; the task lands in failed/.
            if ! sh "$BASE_DIR/scripts/tools/nginx/test-config.sh" >>"$LOG" 2>&1 \
                || ! sh "$BASE_DIR/scripts/tools/nginx/reload.sh" >>"$LOG" 2>&1; then
                log "ERROR: nginx reload failed after compose up"
                exit 1
            fi
            log "nginx reloaded"
        else
            # `down` already stopped the old containers, so restoring only the
            # repo files would leave the site OFFLINE. Restore the previous code
            # AND bring its containers back up so the last-working version keeps
            # serving.
            log "Docker Compose UP FAILED → restoring previous version and bringing it back up"
            restore_backup
            revert_static_publish
            if sh "$COMPOSE_CMD" "$REPO_LOCATION" up -d --build --force-recreate >>"$LOG" 2>&1; then
                log "Previous version restored and running"
            else
                log "WARNING: could not bring previous version back up — site may be DOWN, manual intervention required"
            fi
            mv "$TASK_FILE" "$PROCESSED_DIR/$(basename "$TASK_FILE").failed.$(date +%s)" 2>/dev/null || true
            exit 1
        fi
    else
        log "ERROR: DOCKER_COMPOSE_RESTART_REQUIRED=YES but no compose file(s) found under '$REPO_LOCATION' → restoring"
        restore_backup
        revert_static_publish
        mv "$TASK_FILE" "$PROCESSED_DIR/$(basename "$TASK_FILE").failed.$(date +%s)" 2>/dev/null || true
        exit 1
    fi
fi

# --- Success: move task file ---
mv "$TASK_FILE" "$PROCESSED_DIR/$(basename "$TASK_FILE").$(date +%s)" 2>/dev/null || true
log "Redeploy SUCCESS"