#!/bin/sh
# env-setup.sh - MUST be in repo root
# Sets BASE_DIR and all paths robustly

# Always resolve this file’s directory, not the caller’s
if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
  SELF=$(readlink -f "$0" 2>/dev/null || echo "$0")
else
  # Fallback: assume this script is executed directly or sourced from its own dir
  case "$0" in
    /*) SELF="$0" ;;
    *) SELF="$(pwd)/$0" ;;
  esac
fi

# If sourced, BASH_SOURCE[0] isn’t available in sh — use dirname of this file directly
BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$SELF")" && pwd)

export BASE_DIR
export ORCHESTRATOR_DIR="$BASE_DIR/orchestrator"
export PROJECTS_DIR="$BASE_DIR/projects"
export CONF_DIR="$ORCHESTRATOR_DIR/servers-confs"
export CERTS_DIR="$ORCHESTRATOR_DIR/data/certs"
export WEBROOT_DIR="$ORCHESTRATOR_DIR/data/certbot-webroot"
export SHARED_FILES="/shared-files"
export SCRIPT_DIR="$BASE_DIR/scripts"

# Validate mandatory dirs
for d in "$ORCHESTRATOR_DIR" "$PROJECTS_DIR"; do
  [ ! -d "$d" ] && {
    echo "ERROR: Missing directory: $d" >&2
    exit 1
  }
done
