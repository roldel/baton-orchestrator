#!/bin/sh
# Check nginx syntax inside the running ingress-nginx container
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
COMPOSE_FILE="$ROOT/orchestrator/docker-compose.yml"

echo "[nginx-syntax] Validating Nginx configuration…"
docker compose -f "$COMPOSE_FILE" exec nginx nginx -t
echo "[nginx-syntax] ✅ Nginx configuration is valid"
