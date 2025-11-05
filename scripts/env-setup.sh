#!/bin/sh
# scripts/env-setup.sh
# Sets BASE_DIR and all paths — works from any script

# Find repo root: prefer git, fallback to script location
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BASE_DIR=$(git rev-parse --show-toplevel)
else
    # Resolve via this script's real path
    _self=$(readlink -f "$0" 2>/dev/null || echo "$0")
    BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$_self")/.." && pwd)
fi

export BASE_DIR
export ORCHESTRATOR_DIR="$BASE_DIR/orchestrator"
export PROJECTS_DIR="$BASE_DIR/projects"
export CONF_DIR="$ORCHESTRATOR_DIR/servers-confs"
export CERTS_DIR="$ORCHESTRATOR_DIR/data/certs"
export WEBROOT_DIR="$ORCHESTRATOR_DIR/data/certbot-webroot"
export SHARED_FILES="/shared-files"

# Validate structure
for d in "$ORCHESTRATOR_DIR" "$PROJECTS_DIR" "$CONF_DIR"; do
    [ ! -d "$d" ] && {
        echo "ERROR: Missing directory: $d" >&2
        exit 1
    }
done