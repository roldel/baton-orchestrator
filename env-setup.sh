#!/bin/sh
# env-setup.sh - defines base directories for Baton Orchestrator
# Works everywhere: Alpine, BusyBox, sourced or executed

set -eu

# If BASE_DIR not passed in by baton, derive it relative to this file
: "${BASE_DIR:=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"

export BASE_DIR
export ORCHESTRATOR_DIR="$BASE_DIR/orchestrator"
export PROJECTS_DIR="$BASE_DIR/projects"
export CONF_DIR="$ORCHESTRATOR_DIR/servers-confs"
export CERTS_DIR="$ORCHESTRATOR_DIR/data/certs"
export WEBROOT_DIR="$ORCHESTRATOR_DIR/data/certbot-webroot"
export SHARED_FILES="/shared-files"
export SCRIPT_DIR="$BASE_DIR/scripts"

for d in "$ORCHESTRATOR_DIR" "$PROJECTS_DIR"; do
  [ -d "$d" ] || { echo "ERROR: Missing directory: $d" >&2; exit 1; }
done
