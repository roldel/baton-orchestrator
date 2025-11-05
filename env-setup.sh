#!/bin/sh
# env-setup.sh - MUST be in repo root
# Works when sourced from anywhere (baton, cmd/, tools/...)

set -eu

# Find repo root by walking up from this script’s directory, not $0
# Use this script’s actual location even when sourced
SCRIPT_PATH="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE:-$0}")" 2>/dev/null && pwd || pwd)"
BASE_DIR=$(CDPATH= cd -- "$SCRIPT_PATH" && pwd)

export BASE_DIR
export ORCHESTRATOR_DIR="$BASE_DIR/orchestrator"
export PROJECTS_DIR="$BASE_DIR/projects"
export CONF_DIR="$ORCHESTRATOR_DIR/servers-confs"
export CERTS_DIR="$ORCHESTRATOR_DIR/data/certs"
export WEBROOT_DIR="$ORCHESTRATOR_DIR/data/certbot-webroot"
export SHARED_FILES="/shared-files"
export SCRIPT_DIR="$BASE_DIR/scripts"

# Validate required directories
for d in "$ORCHESTRATOR_DIR" "$PROJECTS_DIR"; do
    if [ ! -d "$d" ]; then
        echo "ERROR: Missing directory: $d" >&2
        exit 1
    fi
done
