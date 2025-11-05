#!/bin/sh
# env-setup.sh - Sets BASE_DIR and paths
# Must be in repo root: /opt/baton-orchestrator/env-setup.sh

# Resolve repo root via this file's location
SELF=$(readlink -f "$0" 2>/dev/null || echo "$0")
BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$SELF")" && pwd)

export BASE_DIR
export ORCHESTRATOR_DIR="$BASE_DIR/orchestrator"
export PROJECTS_DIR="$BASE_DIR/projects"
export CONF_DIR="$ORCHESTRATOR_DIR/servers-confs"
export CERTS_DIR="$ORCHESTRATOR_DIR/data/certs"
export WEBROOT_DIR="$ORCHESTRATOR_DIR/data/certbot-webroot"
export SHARED_FILES="/shared-files"

# Validate
for d in "$ORCHESTRATOR_DIR" "$PROJECTS_DIR"; do
    [ ! -d "$d" ] && {
        echo "ERROR: Missing directory: $d" >&2
        exit 1
    }
done