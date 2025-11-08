#!/bin/sh
# Usage: ./scripts/manual/caddy-reload.sh
set -eu

COMPOSE_FILE="orchestrator/docker-compose.yml"
SERVICE="caddy"
CONFIG_PATH="/etc/caddy/Caddyfile"

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "ERROR: docker compose not found" >&2
  exit 1
fi

echo "[caddy-reload] Reloading config..."
set -x
$COMPOSE -f "$COMPOSE_FILE" exec -T "$SERVICE" \
  caddy reload --config "$CONFIG_PATH" --adapter caddyfile
set +x
echo "[caddy-reload] ✅ Reload complete."




# docker compose -f orchestrator/docker-compose.yml exec caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile