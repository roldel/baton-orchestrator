#!/bin/sh
# scripts/cleanup.sh
# Robust cleanup for baton-orchestrator
# Removes: CLI, configs, certs, dirs, network, shared files
# Run with: sudo ./scripts/cleanup.sh
# WARNING: Irreversible!

set -e

# ------------------------------------------------------------------
# 1. Resolve repo root
# ------------------------------------------------------------------
if [ -L "$0" ]; then
    REAL_PATH=$(readlink -f "$0")
else
    REAL_PATH="$0"
fi
REAL_DIR=$(CDPATH= cd -- "$(dirname -- "$REAL_PATH")" && pwd)
BASE_DIR=$(CDPATH= cd -- "$REAL_DIR/.." && pwd)

echo "Cleaning baton-orchestrator from: $BASE_DIR"
echo "THIS WILL DELETE ALL CONFIGS, CERTS, AND SHARED FILES!"
printf "Type YES to continue: "
read -r confirm
[ "$confirm" != "YES" ] && { echo "Aborted."; exit 1; }

# ------------------------------------------------------------------
# 2. Stop orchestrator containers (if running)
# ------------------------------------------------------------------
if docker compose -f "$BASE_DIR/orchestrator/docker-compose.yml" ps -q >/dev/null 2>&1; then
    echo "Stopping orchestrator..."
    docker compose -f "$BASE_DIR/orchestrator/docker-compose.yml" down -v || true
fi

# ------------------------------------------------------------------
# 3. Remove baton CLI
# ------------------------------------------------------------------
BATON_DEST="/usr/local/bin/baton"
if [ -f "$BATON_DEST" ] || [ -L "$BATON_DEST" ]; then
    rm -f "$BATON_DEST"
    echo "Removed $BATON_DEST"
fi

# ------------------------------------------------------------------
# 4. Remove Docker network
# ------------------------------------------------------------------
if docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
    echo "Removing network: internal_proxy_pass_network"
    docker network rm internal_proxy_pass_network || true
fi

# ------------------------------------------------------------------
# 5. Remove repo data dirs
# ------------------------------------------------------------------
echo "Removing data directories..."
rm -rf "$BASE_DIR/orchestrator/data"
rm -rf "$BASE_DIR/orchestrator/servers-confs"

# ------------------------------------------------------------------
# 6. Remove shared files (ALL sites!)
# ------------------------------------------------------------------
if [ -d /shared-files ]; then
    echo "Removing /shared-files (all static/media)"
    rm -rf /shared-files/*
    rmdir /shared-files 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 7. Optional: Remove entire repo
# ------------------------------------------------------------------
printf "Remove entire repo directory? (YES to delete $BASE_DIR): "
read -r remove_repo
if [ "$remove_repo" = "YES" ]; then
    cd /
    rm -rf "$BASE_DIR"
    echo "Deleted $BASE_DIR"
else
    echo "Repo kept at $BASE_DIR"
fi

echo ""
echo "Cleanup complete. System is neutral."
echo "To reinstall: git clone ... && sudo ./scripts/setup.sh"