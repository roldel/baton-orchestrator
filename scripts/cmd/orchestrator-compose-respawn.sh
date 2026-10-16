#!/bin/sh
# scripts/cmd/orchestrator-compose-respawn.sh
# Full respawn of the orchestrator stack itself (nginx, webhook listener, etc).
#
# Optionally implement log stats snapshot before container logs get reset and lost upon container rebuild

set -eu

COMPOSE_FILE="/opt/baton-orchestrator/orchestrator/docker-compose.yml"

# Tolerated like restart-containers.sh's identical `down` call: a transient
# failure (busy daemon, network-removal race, a stuck container) must not
# abort before `up` runs, or the whole orchestrator stack (nginx, webhook
# listener) stays down until someone notices and reruns this manually.
docker compose -f "$COMPOSE_FILE" down || {
  echo "WARNING: docker compose down failed for the orchestrator stack (containers may already be stopped)." >&2
}
docker compose -f "$COMPOSE_FILE" up -d --build --force-recreate
