#!/bin/sh
# scripts/cmd/orchestrator-compose-respawn.sh
# Full respawn of the orchestrator stack itself (nginx, webhook listener, etc).
#
# Optionally implement log stats snapshot before container logs get reset and lost upon container rebuild

set -eu

COMPOSE_FILE="/opt/baton-orchestrator/orchestrator/docker-compose.yml"

docker compose -f "$COMPOSE_FILE" down
docker compose -f "$COMPOSE_FILE" up -d --build --force-recreate
