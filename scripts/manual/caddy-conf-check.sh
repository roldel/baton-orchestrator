#!/bin/sh
# Usage: ./scripts/manual/caddy-conf-check.sh <project-name>
# Validates /etc/caddy/conf.d/<project>.conf inside the "caddy" container
# using your compose file at orchestrator/docker-compose.yml.

set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

COMPOSE_FILE="orchestrator/docker-compose.yml"
SERVICE="caddy"
CONF_PATH="/etc/caddy/conf.d/$PROJECT.conf"

# Pick docker compose flavor (v2 `docker compose` preferred; fallback to old `docker-compose`)
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "ERROR: docker compose not found. Install Docker Compose v2 or v1." >&2
  exit 1
fi

echo "[caddy-check] Compose file: $COMPOSE_FILE"
echo "[caddy-check] Service:      $SERVICE"
echo "[caddy-check] Config path:  $CONF_PATH"
echo "[caddy-check] Adapter:      caddyfile"

# Use -T to disable TTY so the exit code propagates cleanly
set -x
$COMPOSE -f "$COMPOSE_FILE" exec -T "$SERVICE" \
  caddy validate --config "$CONF_PATH" --adapter caddyfile
set +x

echo "[caddy-check] ✅ Validation succeeded for $CONF_PATH"





#docker compose -f orchestrator/docker-compose.yml exec
# caddy validate --config /etc/caddy/conf.d/demo-website.conf --adapter caddyfile