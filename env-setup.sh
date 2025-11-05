#!/bin/sh
# env-setup.sh — location-agnostic; expects BASE_DIR from baton (derives if missing)
set -eu

: "${BASE_DIR:=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"

export BASE_DIR
export ORCHESTRATOR_DIR="$BASE_DIR/orchestrator"
export PROJECTS_DIR="$BASE_DIR/projects"
export CONF_DIR="$ORCHESTRATOR_DIR/servers-confs"
export CERTS_DIR="$ORCHESTRATOR_DIR/data/certs"
export WEBROOT_DIR="$ORCHESTRATOR_DIR/data/certbot-webroot"
export SHARED_FILES="/shared-files"
export SCRIPT_DIR="$BASE_DIR/scripts"

# Optional strict install policy (set STRICT_INSTALL=1 to enforce /opt)
REQUIRED_BASE="/opt/baton-orchestrator"
if [ "${STRICT_INSTALL:=0}" = "1" ] && [ "$BASE_DIR" != "$REQUIRED_BASE" ]; then
  echo "ERROR: expected $REQUIRED_BASE (found $BASE_DIR). Set STRICT_INSTALL=0 to override." >&2
  exit 1
fi

for d in "$ORCHESTRATOR_DIR" "$PROJECTS_DIR"; do
  [ -d "$d" ] || { echo "ERROR: Missing directory: $d" >&2; exit 1; }
done
