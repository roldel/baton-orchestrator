#!/bin/sh
# Run once as root on Alpine (OpenRC)
set -eu

: "${BASE_DIR:=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"

echo "Setting up baton-orchestrator in: $BASE_DIR"

#-------------#
# Dependencies
#-------------#
if command -v apk >/dev/null 2>&1; then
  echo "Installing required packages via apk..."
  # docker + compose v2, git, gettext (envsubst), cron daemon, inotify tools
  apk update >/dev/null
  apk add --no-cache \
    docker \
    docker-cli-compose \
    git \
    gettext \
    inotify-tools >/dev/null

  # Enable & start Docker (OpenRC)
  rc-update add docker default >/dev/null || true
  rc-service docker start || true

else
  echo "apk not found; skipping package install (this script targets Alpine)."
fi

#----------------#
# Host filesystem
#----------------#
mkdir -p \
  "$BASE_DIR/orchestrator/data/certs" \
  "$BASE_DIR/orchestrator/data/certbot-webroot" \
  "$BASE_DIR/orchestrator/server-confs" \
  "$BASE_DIR/orchestrator/webhook-redeploy-instruct" \
  /shared-files \
  /usr/local/bin

#--------------------#
# Docker prerequisites
#--------------------#
if command -v docker >/dev/null 2>&1; then
  if ! docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
    echo "Creating Docker network: internal_proxy_pass_network"
    docker network create internal_proxy_pass_network
  else
    echo "Network already exists"
  fi

  # Optional: verify compose v2 is available
  if ! docker compose version >/dev/null 2>&1; then
    echo "WARNING: 'docker compose' not available. Ensure docker-cli-compose is installed."
  fi
else
  echo "WARNING: Docker not found on PATH. Install/enable Docker before deploying."
fi

#-------------------#
# Baton CLI symlink
#-------------------#
BATON_SRC="$BASE_DIR/scripts/baton"
BATON_DEST="/usr/local/bin/baton"

echo "Installing baton → $BATON_DEST"
ln -sf "$BATON_SRC" "$BATON_DEST"
chmod +x "$BATON_SRC"

echo
echo "Setup complete!"
echo "Run: baton deploy demo-website"
