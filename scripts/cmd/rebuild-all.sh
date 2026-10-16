#!/bin/sh
# scripts/cmd/rebuild-all.sh
# Force a full respawn of all Baton-managed projects (or a filtered subset).
#
# For each project, runs respawn.sh which:
#   1. Preserves webhook active state
#   2. Stands down the project
#   3. Deploys fresh (down → up --build --force-recreate, or re-syncs static files)
#   4. Restores webhook if it was active
#
# With --activate-webhooks, each successful respawn is followed by
# webhook-activate.sh when the project's .env already has DOMAIN_NAME,
# WEBHOOK_URL, and PAYLOAD_SIGNATURE and the nginx snippet is absent.
# Incomplete webhook settings are skipped. An existing snippet is left alone
# (respawn already restored it).
#
# Usage:
#   ./scripts/cmd/rebuild-all.sh                      # all projects
#   ./scripts/cmd/rebuild-all.sh --mode dynamic        # dynamic projects only
#   ./scripts/cmd/rebuild-all.sh --mode static         # static projects only
#   ./scripts/cmd/rebuild-all.sh --dry-run             # print what would run, do nothing
#   ./scripts/cmd/rebuild-all.sh --mode dynamic --dry-run
#   ./scripts/cmd/rebuild-all.sh --activate-webhooks
#   ./scripts/cmd/rebuild-all.sh --activate-webhooks --dry-run

set -eu

BASE_DIR="/opt/baton-orchestrator"
PROJECTS_ROOT="/srv/projects"
CMD_DIR="$BASE_DIR/scripts/cmd"
WEBHOOKS_DIR="/srv/baton-orchestrator/webhooks.d"

# --- Parse arguments ---
MODE_FILTER=""
DRY_RUN=0
ACTIVATE_WEBHOOKS=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            [ "$#" -lt 2 ] && { echo "ERROR: --mode requires a value (dynamic|static)" >&2; exit 1; }
            MODE_FILTER="$2"
            case "$MODE_FILTER" in
                dynamic|static) ;;
                *) echo "ERROR: --mode must be 'dynamic' or 'static'" >&2; exit 1 ;;
            esac
            shift 2
            ;;
        --activate-webhooks)
            ACTIVATE_WEBHOOKS=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--mode dynamic|static] [--activate-webhooks] [--dry-run]

Force a full respawn of all Baton-managed projects.

Options:
  --mode dynamic|static   Only process projects of the given deploy mode
  --activate-webhooks     After a successful respawn, activate the webhook
                          when DOMAIN_NAME, WEBHOOK_URL, and PAYLOAD_SIGNATURE
                          are set and the nginx snippet is not already installed.
                          Projects with incomplete webhook settings are skipped.
  --dry-run               Print what would be rebuilt without doing anything
  -h, --help              Show this help
EOF
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Decide what --activate-webhooks would do for one project.
# Sets WEBHOOK_PLAN to: activate | already-active | skip
# Clears the three webhook vars before sourcing so an earlier project cannot leak.
classify_webhook() {
    _project="$1"
    _env="$PROJECTS_ROOT/$_project/.env"

    DOMAIN_NAME=""
    WEBHOOK_URL=""
    PAYLOAD_SIGNATURE=""
    WEBHOOK_PLAN="skip"

    if [ ! -f "$_env" ]; then
        return 0
    fi

    # Read in isolated subshells, not sourced into this shell directly: this
    # function is called once per project, and a project's .env sourced
    # directly could redefine CMD_DIR/WEBHOOKS_DIR/etc. for the REST of this
    # script's run — hijacking which script executes for every other
    # project. `set +eu` keeps a malformed .env from aborting under set -eu.
    DOMAIN_NAME="$(
        set +eu
        . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
        if load_env_safe "$_env"; then
            printf '%s' "${DOMAIN_NAME:-}"
        fi
    )"
    WEBHOOK_URL="$(
        set +eu
        . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
        if load_env_safe "$_env"; then
            printf '%s' "${WEBHOOK_URL:-}"
        fi
    )"
    PAYLOAD_SIGNATURE="$(
        set +eu
        . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
        if load_env_safe "$_env"; then
            printf '%s' "${PAYLOAD_SIGNATURE:-}"
        fi
    )"

    if [ -z "${DOMAIN_NAME:-}" ] || [ -z "${WEBHOOK_URL:-}" ] || [ -z "${PAYLOAD_SIGNATURE:-}" ]; then
        WEBHOOK_PLAN="skip"
        return 0
    fi

    if [ -f "$WEBHOOKS_DIR/${DOMAIN_NAME}-webhook.conf" ]; then
        WEBHOOK_PLAN="already-active"
        return 0
    fi

    WEBHOOK_PLAN="activate"
}

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

# --- Collect projects ---
if [ ! -d "$PROJECTS_ROOT" ] || [ -z "$(ls -A "$PROJECTS_ROOT" 2>/dev/null)" ]; then
    echo "No projects found under $PROJECTS_ROOT"
    exit 0
fi

# By now the argument parser above has consumed every script argument (it
# shift'd each recognized flag and exits on anything else), so "$@" is free
# to reuse here. Built via positional params, not a space-joined string: a
# project directory name containing a space would otherwise be word-split by
# `for X in $LIST` and silently excluded from the rebuild with no error.
set --
for PROJECT_DIR in "$PROJECTS_ROOT"/*; do
    [ -d "$PROJECT_DIR" ] || continue
    PROJECT="${PROJECT_DIR##*/}"

    # Read in an isolated subshell, not sourced into this shell directly:
    # this runs once per project before CMD_DIR is used in the rebuild loop
    # below, so a project's .env sourced directly here could redefine CMD_DIR
    # (or any other variable this script relies on) for the rest of the run.
    ENV_FILE="$PROJECT_DIR/.env"
    STATIC_SITE="no"
    if [ -f "$ENV_FILE" ]; then
        STATIC_SITE="$(
            set +eu
            . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
            if load_env_safe "$ENV_FILE"; then
                printf '%s' "${STATIC_SITE:-no}"
            fi
        )"
        [ -n "$STATIC_SITE" ] || STATIC_SITE="no"
    fi

    if [ "$STATIC_SITE" = "yes" ]; then
        PROJECT_MODE="static"
    else
        PROJECT_MODE="dynamic"
    fi

    if [ -n "$MODE_FILTER" ] && [ "$PROJECT_MODE" != "$MODE_FILTER" ]; then
        continue
    fi

    set -- "$@" "$PROJECT"
done

if [ $# -eq 0 ]; then
    echo "No matching projects found${MODE_FILTER:+ with mode=$MODE_FILTER}."
    exit 0
fi

# --- Summary ---
TARGET_COUNT=$#
echo "======================================================"
echo " Baton Rebuild-All"
echo "======================================================"
echo " Projects  : $TARGET_COUNT"
[ -n "$MODE_FILTER" ] && echo " Mode      : $MODE_FILTER" || echo " Mode      : all"
if [ "$ACTIVATE_WEBHOOKS" -eq 1 ]; then
    echo " Webhooks  : activate where .env is complete"
else
    echo " Webhooks  : preserve existing only"
fi
[ "$DRY_RUN" -eq 1 ]  && echo " Dry run   : YES — no changes will be made"
echo "------------------------------------------------------"
for PROJECT in "$@"; do
    if [ "$ACTIVATE_WEBHOOKS" -eq 1 ]; then
        classify_webhook "$PROJECT"
        case "$WEBHOOK_PLAN" in
            activate)       echo "   - $PROJECT  (webhook: activate)" ;;
            already-active) echo "   - $PROJECT  (webhook: already active)" ;;
            *)              echo "   - $PROJECT  (webhook: skip, settings incomplete)" ;;
        esac
    else
        echo "   - $PROJECT"
    fi
done
echo "======================================================"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run complete. Exiting."
    exit 0
fi

# --- Rebuild loop ---
# Lists below accumulate as newline-delimited strings, not space-joined: a
# project name containing a space must stay one entry when the final report
# below is split back apart (filesystem paths can't contain a newline, so
# it's a safe separator; a space is not).
NL='
'
SUCCEEDED=""
FAILED=""
WEBHOOK_ACTIVATED=""
WEBHOOK_SKIPPED=""
WEBHOOK_ALREADY=""
WEBHOOK_FAILED=""

for PROJECT in "$@"; do
    echo ""
    echo "======================================================"
    echo " Rebuilding: $PROJECT"
    echo "======================================================"

    if sh "$CMD_DIR/respawn.sh" "$PROJECT"; then
        echo "[rebuild-all] ✅ $PROJECT — OK"
        SUCCEEDED="$SUCCEEDED$PROJECT$NL"

        # Classified again after respawn: a snippet that respawn just restored
        # must not be passed to webhook-activate.sh (it errors if the file exists).
        if [ "$ACTIVATE_WEBHOOKS" -eq 1 ]; then
            classify_webhook "$PROJECT"
            case "$WEBHOOK_PLAN" in
                skip)
                    echo "[rebuild-all] $PROJECT — webhook settings incomplete, skipping activation"
                    WEBHOOK_SKIPPED="$WEBHOOK_SKIPPED$PROJECT$NL"
                    ;;
                already-active)
                    echo "[rebuild-all] $PROJECT — webhook already active"
                    WEBHOOK_ALREADY="$WEBHOOK_ALREADY$PROJECT$NL"
                    ;;
                activate)
                    echo "[rebuild-all] $PROJECT — activating webhook"
                    if sh "$CMD_DIR/webhook-activate.sh" "$PROJECT"; then
                        echo "[rebuild-all] ✅ $PROJECT — webhook activated"
                        WEBHOOK_ACTIVATED="$WEBHOOK_ACTIVATED$PROJECT$NL"
                    else
                        echo "[rebuild-all] ❌ $PROJECT — webhook activation FAILED (site rebuild succeeded)"
                        WEBHOOK_FAILED="$WEBHOOK_FAILED$PROJECT$NL"
                    fi
                    ;;
            esac
        fi
    else
        echo "[rebuild-all] ❌ $PROJECT — FAILED (continuing with remaining projects)"
        FAILED="$FAILED$PROJECT$NL"
    fi
done

# --- Final report ---
echo ""
echo "======================================================"
echo " Rebuild-All Complete"
echo "======================================================"

# Splits one of the newline-delimited lists built above back into lines,
# without touching the script's own IFS/positional state.
print_list() {
    printf '%s' "$1" | while IFS= read -r p; do
        [ -n "$p" ] && echo "    - $p"
    done
}

if [ -n "$SUCCEEDED" ]; then
    echo " ✅ Succeeded:"
    print_list "$SUCCEEDED"
fi

if [ -n "$FAILED" ]; then
    echo " ❌ Failed:"
    print_list "$FAILED"
fi

if [ "$ACTIVATE_WEBHOOKS" -eq 1 ]; then
    if [ -n "$WEBHOOK_ACTIVATED" ]; then
        echo " Webhooks activated:"
        print_list "$WEBHOOK_ACTIVATED"
    fi
    if [ -n "$WEBHOOK_ALREADY" ]; then
        echo " Webhooks already active:"
        print_list "$WEBHOOK_ALREADY"
    fi
    if [ -n "$WEBHOOK_SKIPPED" ]; then
        echo " Webhooks skipped (settings incomplete):"
        print_list "$WEBHOOK_SKIPPED"
    fi
    if [ -n "$WEBHOOK_FAILED" ]; then
        echo " ❌ Webhook activation failed (site rebuild succeeded):"
        print_list "$WEBHOOK_FAILED"
    fi
fi

if [ -n "$FAILED" ] || [ -n "$WEBHOOK_FAILED" ]; then
    echo ""
    echo "Check logs above for details on failed projects."
    exit 1
fi

echo ""
echo "All projects rebuilt successfully."
