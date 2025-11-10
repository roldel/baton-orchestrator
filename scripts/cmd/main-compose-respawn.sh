#!/bin/sh
# Restart the main orchestrator Docker Compose stack: down, then up with build and force-recreate.
set -eu

# Resolve BASE_DIR
THIS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "$THIS_DIR/../.." && pwd)"
export BASE_DIR

COMPOSE_FILE="$BASE_DIR/orchestrator/docker-compose.yml"

echo "[main-compose-respawn] Bringing down orchestrator services..."
docker compose -f "$COMPOSE_FILE" down

echo "[main-compose-respawn] Bringing up orchestrator services (build, force-recreate, detached)..."
docker compose -f "$COMPOSE_FILE" up --build --force-recreate -d

echo "[main-compose-respawn] Orchestrator services restarted."