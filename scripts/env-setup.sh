#!/bin/sh
# scripts/env-setup.sh
# Must be sourced by every script

# ------------------------------------------------------------------
# Find repo root (git → fallback to script location)
# ------------------------------------------------------------------
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BASE_DIR=$(git rev-parse --show-toplevel)
else
    # Called via symlink → resolve real path
    _real=$(readlink -f "$0" 2>/dev/null || echo "$0")
    BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$_real")/.." && pwd)
fi

# ------------------------------------------------------------------
# Export everything a command will need
# ------------------------------------------------------------------
export BASE_DIR
export ORCHESTRATOR_DIR="$BASE_DIR/orchestrator"
export PROJECTS_DIR="$BASE_DIR/projects"
export CONF_DIR="$ORCHESTRATOR_DIR/servers-confs"
export CERTS_DIR="$ORCHESTRATOR_DIR/data/certs"
export WEBROOT_DIR="$ORCHESTRATOR_DIR/data/certbot-webroot"
export SHARED_FILES="/shared-files"

# ------------------------------------------------------------------
# Basic sanity check
# ------------------------------------------------------------------
for d in "$ORCHESTRATOR_DIR" "$PROJECTS_DIR" "$CONF_DIR"; do
    if [ ! -d "$d" ]; then
        echo "ERROR: Required directory missing: $d" >&2
        exit 1
    fi
done