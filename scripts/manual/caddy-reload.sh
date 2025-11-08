#!/bin/sh
# Usage: ./scripts/manual/caddy-reload.sh
# Restarts the Caddy service to apply config changes (admin API is disabled)
set -eu

COMPOSE_FILE="orchestrator/docker-compose.yml"
SERVICE="caddy"

# Detect docker compose (v2) or docker-compose (v1)
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "ERROR: docker compose not found" >&2
  exit 1
fi

echo "[caddy-reload] Admin API disabled — restarting Caddy container to apply config..."
set -x
$COMPOSE -f "$COMPOSE_FILE" restart "$SERVICE"
set +x

echo "[caddy-reload] Caddy container restarted."