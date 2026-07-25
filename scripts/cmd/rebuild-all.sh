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
# Usage:
#   ./scripts/cmd/rebuild-all.sh                      # all projects
#   ./scripts/cmd/rebuild-all.sh --mode dynamic        # dynamic projects only
#   ./scripts/cmd/rebuild-all.sh --mode static         # static projects only
#   ./scripts/cmd/rebuild-all.sh --dry-run             # print what would run, do nothing
#   ./scripts/cmd/rebuild-all.sh --mode dynamic --dry-run

set -eu

BASE_DIR="/opt/baton-orchestrator"
PROJECTS_ROOT="/srv/projects"
CMD_DIR="$BASE_DIR/scripts/cmd"

# --- Parse arguments ---
MODE_FILTER=""
DRY_RUN=0

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
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--mode dynamic|static] [--dry-run]

Force a full respawn of all Baton-managed projects.

Options:
  --mode dynamic|static   Only process projects of the given deploy mode
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
[ "$DRY_RUN" -eq 1 ]  && echo " Dry run   : YES — no changes will be made"
echo "------------------------------------------------------"
for PROJECT in $TARGETS; do
    echo "   - $PROJECT"
done
echo "======================================================"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run complete. Exiting."
    exit 0
fi

# --- Rebuild loop ---
SUCCEEDED=""
FAILED=""

for PROJECT in $TARGETS; do
    echo ""
    echo "======================================================"
    echo " Rebuilding: $PROJECT"
    echo "======================================================"

    if sh "$CMD_DIR/respawn.sh" "$PROJECT"; then
        echo "[rebuild-all] ✅ $PROJECT — OK"
        SUCCEEDED="$SUCCEEDED $PROJECT"
    else
        echo "[rebuild-all] ❌ $PROJECT — FAILED (continuing with remaining projects)"
        FAILED="$FAILED $PROJECT"
    fi
done

# --- Final report ---
SUCCEEDED="${SUCCEEDED# }"
FAILED="${FAILED# }"

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
    echo ""
    echo "Check logs above for details on failed projects."
    exit 1
fi

echo ""
echo "All projects rebuilt successfully."
