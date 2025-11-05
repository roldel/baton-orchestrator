#!/bin/sh
# scripts/setup.sh - Run once as root (no sudo on Alpine)

set -eu

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
echo "Setting up baton-orchestrator in: $BASE_DIR"

mkdir -p "$BASE_DIR/orchestrator/data/certs" \
         "$BASE_DIR/orchestrator/data/certbot-webroot" \
         "$BASE_DIR/orchestrator/servers-confs" \
         /shared-files \
         /usr/local/bin

if ! docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
  echo "Creating Docker network: internal_proxy_pass_network"
  docker network create internal_proxy_pass_network
else
  echo "Network already exists"
fi

BATON_SRC="$BASE_DIR/scripts/baton"
BATON_DEST="/usr/local/bin/baton"

echo "Installing baton → $BATON_DEST"
ln -sf "$BATON_SRC" "$BATON_DEST"
chmod +x "$BATON_SRC"

# Create directory used by webhook bind mount (see compose)
mkdir -p "$BASE_DIR/orchestrator/webhook-redeploy-instruct"

echo
echo "Setup complete!"
echo "Run: baton deploy demo-website"
