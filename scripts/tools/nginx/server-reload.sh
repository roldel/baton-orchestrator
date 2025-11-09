#!/bin/sh
# Reload nginx in the running container
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
COMPOSE_FILE="$ROOT/orchestrator/docker-compose.yml"

echo "[nginx-reload] Reloading Nginx…"
docker compose -f "$COMPOSE_FILE" exec nginx nginx -s reload
echo "[nginx-reload] ✅ Reloaded"
