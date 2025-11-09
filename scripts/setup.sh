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
  apk update >/dev/null
  apk add --no-cache \
    docker \
    docker-cli-compose \
    git \
    gettext \
    openssl \
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
  /shared-files

#--------------------#
# Docker prerequisites
#--------------------#
if command -v docker >/dev/null 2>&1; then
  # Create network if missing
  if ! docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
    echo "Creating Docker network: internal_proxy_pass_network"
    docker network create internal_proxy_pass_network
  else
    echo "Network already exists: internal_proxy_pass_network"
  fi

  # Optional: verify compose v2
  if ! docker compose version >/dev/null 2>&1; then
    echo "WARNING: 'docker compose' not available. Ensure docker-cli-compose is installed."
  fi
else
  echo "WARNING: Docker not found on PATH. Install/enable Docker before deploying."
fi

#--------------------#
# Orchestrator Services: Clean Start
#--------------------#
ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"

if [ -f "$ORCHESTRATOR_COMPOSE" ]; then
  echo "Stopping any existing orchestrator services (clean state)..."
  docker compose -f "$ORCHESTRATOR_COMPOSE" down --remove-orphans || true

  echo "Starting nginx (certbot starts on-demand with sleep infinity)..."
  docker compose -f "$ORCHESTRATOR_COMPOSE" up -d nginx
else
  echo "ERROR: Missing $ORCHESTRATOR_COMPOSE" >&2
  exit 1
fi

echo
echo "Setup complete!"
echo "   Nginx is running"
echo "   Certbot will start on-demand during first deploy"
echo "   Run: ./scripts/cmd/deploy.sh <project-name>"