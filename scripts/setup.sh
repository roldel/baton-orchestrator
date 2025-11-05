#!/bin/sh
# scripts/setup.sh - Run once with sudo

set -e

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
echo "Setting up baton-orchestrator in: $BASE_DIR"

# Create required dirs
mkdir -p "$BASE_DIR/orchestrator/data/certs"
mkdir -p "$BASE_DIR/orchestrator/data/certbot-webroot"
mkdir -p "$BASE_DIR/orchestrator/servers-confs"
mkdir -p /shared-files

# Docker network
if ! docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
    echo "Creating Docker network: internal_proxy_pass_network"
    docker network create internal_proxy_pass_network
else
    echo "Network already exists"
fi

# Install CLI
BATON_SRC="$BASE_DIR/scripts/baton"
BATON_DEST="/usr/local/bin/baton"

echo "Installing baton → $BATON_DEST"
ln -sf "$BATON_SRC" "$BATON_DEST"
chmod +x "$BATON_SRC"

echo ""
echo "Setup complete!"
echo "Run: baton deploy demo-website"