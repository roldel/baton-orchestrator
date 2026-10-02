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

    # shellcheck source=/dev/null
    . "$_env"

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

PROJECTS="$(ls "$PROJECTS_ROOT")"

# --- Filter by mode if requested ---
TARGETS=""
for PROJECT in $PROJECTS; do
    PROJECT_DIR="$PROJECTS_ROOT/$PROJECT"
    [ -d "$PROJECT_DIR" ] || continue

    # Reset .env-sourced var before each iteration to prevent bleed
    STATIC_SITE="no"

    ENV_FILE="$PROJECT_DIR/.env"
    if [ -f "$ENV_FILE" ]; then
        # shellcheck source=/dev/null
        . "$ENV_FILE"
        STATIC_SITE="${STATIC_SITE:-no}"
    fi

    if [ "$STATIC_SITE" = "yes" ]; then
        PROJECT_MODE="static"
    else
        PROJECT_MODE="dynamic"
    fi

    if [ -n "$MODE_FILTER" ] && [ "$PROJECT_MODE" != "$MODE_FILTER" ]; then
        continue
    fi

    TARGETS="$TARGETS $PROJECT"
done

TARGETS="${TARGETS# }"   # strip leading space

if [ -z "$TARGETS" ]; then
    echo "No matching projects found${MODE_FILTER:+ with mode=$MODE_FILTER}."
    exit 0
fi

# --- Summary ---
TARGET_COUNT="$(echo "$TARGETS" | wc -w | tr -d ' ')"
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
for PROJECT in $TARGETS; do
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
SUCCEEDED=""
FAILED=""
WEBHOOK_ACTIVATED=""
WEBHOOK_SKIPPED=""
WEBHOOK_ALREADY=""
WEBHOOK_FAILED=""

for PROJECT in $TARGETS; do
    echo ""
    echo "======================================================"
    echo " Rebuilding: $PROJECT"
    echo "======================================================"

    if sh "$CMD_DIR/respawn.sh" "$PROJECT"; then
        echo "[rebuild-all] ✅ $PROJECT — OK"
        SUCCEEDED="$SUCCEEDED $PROJECT"

        # Classified again after respawn: a snippet that respawn just restored
        # must not be passed to webhook-activate.sh (it errors if the file exists).
        if [ "$ACTIVATE_WEBHOOKS" -eq 1 ]; then
            classify_webhook "$PROJECT"
            case "$WEBHOOK_PLAN" in
                skip)
                    echo "[rebuild-all] $PROJECT — webhook settings incomplete, skipping activation"
                    WEBHOOK_SKIPPED="$WEBHOOK_SKIPPED $PROJECT"
                    ;;
                already-active)
                    echo "[rebuild-all] $PROJECT — webhook already active"
                    WEBHOOK_ALREADY="$WEBHOOK_ALREADY $PROJECT"
                    ;;
                activate)
                    echo "[rebuild-all] $PROJECT — activating webhook"
                    if sh "$CMD_DIR/webhook-activate.sh" "$PROJECT"; then
                        echo "[rebuild-all] ✅ $PROJECT — webhook activated"
                        WEBHOOK_ACTIVATED="$WEBHOOK_ACTIVATED $PROJECT"
                    else
                        echo "[rebuild-all] ❌ $PROJECT — webhook activation FAILED (site rebuild succeeded)"
                        WEBHOOK_FAILED="$WEBHOOK_FAILED $PROJECT"
                    fi
                    ;;
            esac
        fi
    else
        echo "[rebuild-all] ❌ $PROJECT — FAILED (continuing with remaining projects)"
        FAILED="$FAILED $PROJECT"
    fi
done

# --- Final report ---
SUCCEEDED="${SUCCEEDED# }"
FAILED="${FAILED# }"
WEBHOOK_ACTIVATED="${WEBHOOK_ACTIVATED# }"
WEBHOOK_SKIPPED="${WEBHOOK_SKIPPED# }"
WEBHOOK_ALREADY="${WEBHOOK_ALREADY# }"
WEBHOOK_FAILED="${WEBHOOK_FAILED# }"

echo ""
echo "======================================================"
echo " Rebuild-All Complete"
echo "======================================================"

if [ -n "$SUCCEEDED" ]; then
    echo " ✅ Succeeded:"
    for p in $SUCCEEDED; do echo "    - $p"; done
fi

if [ -n "$FAILED" ]; then
    echo " ❌ Failed:"
    for p in $FAILED; do echo "    - $p"; done
fi

if [ "$ACTIVATE_WEBHOOKS" -eq 1 ]; then
    if [ -n "$WEBHOOK_ACTIVATED" ]; then
        echo " Webhooks activated:"
        for p in $WEBHOOK_ACTIVATED; do echo "    - $p"; done
    fi
    if [ -n "$WEBHOOK_ALREADY" ]; then
        echo " Webhooks already active:"
        for p in $WEBHOOK_ALREADY; do echo "    - $p"; done
    fi
    if [ -n "$WEBHOOK_SKIPPED" ]; then
        echo " Webhooks skipped (settings incomplete):"
        for p in $WEBHOOK_SKIPPED; do echo "    - $p"; done
    fi
    if [ -n "$WEBHOOK_FAILED" ]; then
        echo " ❌ Webhook activation failed (site rebuild succeeded):"
        for p in $WEBHOOK_FAILED; do echo "    - $p"; done
    fi
fi

if [ -n "$FAILED" ] || [ -n "$WEBHOOK_FAILED" ]; then
    echo ""
    echo "Check logs above for details on failed projects."
    exit 1
fi

echo ""
echo "All projects rebuilt successfully."
