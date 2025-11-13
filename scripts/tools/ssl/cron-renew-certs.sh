#!/bin/sh
set -eu

BASE_DIR="/opt/baton-orchestrator"
ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"

echo "[renew] Running certbot renew..."

OUTPUT="$(docker compose -f "$ORCHESTRATOR_COMPOSE" run --rm certbot renew 2>&1 || true)"
echo "$OUTPUT"

if echo "$OUTPUT" | grep -q "Renewing an existing certificate"; then
    echo "[renew] Certificates renewed → reloading nginx..."
    sh "$BASE_DIR/scripts/tools/nginx/reload.sh"
else
    echo "[renew] No renewal needed."
fi
