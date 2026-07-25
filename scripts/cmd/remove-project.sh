#!/bin/sh
# scripts/cmd/remove-project.sh
# Cleanly remove a project from Baton management:
#   1. Deactivate webhook (if active)
#   2. Stand down containers and remove nginx config
#   3. Optionally delete the project directory under /srv/projects
#
# The project's SSL certificate and shared files under /srv/shared-files
# are intentionally preserved — re-deploying the same domain should not
# require re-issuing a cert. Remove them manually if truly decommissioning.
#
# Usage:
#   ./scripts/cmd/remove-project.sh <project-name>
#   ./scripts/cmd/remove-project.sh <project-name> --delete-files

set -eu

BASE_DIR="/opt/baton-orchestrator"
PROJECTS_ROOT="/srv/projects"
CMD_DIR="$BASE_DIR/scripts/cmd"

# --- Parse arguments ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 <project-name> [--delete-files]" >&2
    exit 1
fi

PROJECT="$1"
DELETE_FILES=0

if [ "${2:-}" = "--delete-files" ]; then
    DELETE_FILES=1
fi

PROJECT_DIR="$PROJECTS_ROOT/$PROJECT"

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

# --- Validate project exists ---
if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory not found: $PROJECT_DIR" >&2
    exit 1
fi

echo "======================================================"
echo " Removing project: $PROJECT"
echo "======================================================"
[ "$DELETE_FILES" -eq 1 ] && echo " ⚠️  --delete-files set: $PROJECT_DIR will be deleted"
echo ""

# --- Confirmation prompt when deleting files ---
if [ "$DELETE_FILES" -eq 1 ]; then
    printf "Type the project name to confirm deletion of %s: " "$PROJECT_DIR"
    read -r CONFIRM
    if [ "$CONFIRM" != "$PROJECT" ]; then
        echo "Confirmation did not match. Aborting."
        exit 1
    fi
fi

# --- Step 1: Stand down (deactivates webhook + stops containers + removes nginx config) ---
echo "[remove] Step 1/3 — Standing down project..."
if sh "$CMD_DIR/stand-down.sh" "$PROJECT"; then
    echo "[remove] Stand-down OK."
else
    echo "[remove] WARNING: stand-down encountered an issue. Continuing..." >&2
fi

# --- Step 2: Report what was preserved ---
echo ""
echo "[remove] Step 2/3 — Preserved resources (manual cleanup if needed):"

ENV_FILE="$PROJECT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
    DOMAIN_NAME="${DOMAIN_NAME:-}"

    CERT_DIR="/etc/letsencrypt/live/${DOMAIN_NAME}"
    SHARED_FILES="/srv/shared-files/${DOMAIN_NAME}"

    if [ -n "$DOMAIN_NAME" ]; then
        if [ -d "$CERT_DIR" ]; then
            echo "   SSL cert    : $CERT_DIR  (preserved)"
        fi
        if [ -d "$SHARED_FILES" ]; then
            echo "   Shared files: $SHARED_FILES  (preserved)"
        fi
    fi
fi

# --- Step 3: Optionally delete project directory ---
echo ""
echo "[remove] Step 3/3 — Project directory..."
if [ "$DELETE_FILES" -eq 1 ]; then
    echo "[remove] Deleting $PROJECT_DIR..."
    rm -rf "$PROJECT_DIR"
    echo "[remove] Deleted."
else
    echo "[remove] $PROJECT_DIR kept intact."
    echo "         Run with --delete-files to remove it, or delete manually:"
    echo "         rm -rf $PROJECT_DIR"
fi

echo ""
echo "======================================================"
echo " Project '$PROJECT' removed from Baton management."
echo " SSL certificate and shared files were NOT touched."
echo "======================================================"
