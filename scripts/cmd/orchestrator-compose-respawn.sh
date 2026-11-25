#!/bin/sh
# scripts/cmd/orchestrator-compose-respawn.sh
# Full respawn of the orchestrator stack itself (nginx, webhook listener, etc).
#
# nginx and certbot are pulled images (not built), so plain `up` never
# re-checks the registry for a newer digest under an already-cached tag like
# nginx:alpine. webhook is built from ./webhook (FROM python:3.11-alpine),
# so plain `up --build` has the same local-layer-cache problem project images
# do. --no-cache re-pulls nginx/certbot and rebuilds webhook via
# `build --no-cache --pull`, so all three are guaranteed fresh.
#
# Usage:
#   ./scripts/cmd/orchestrator-compose-respawn.sh              # cached rebuild
#   ./scripts/cmd/orchestrator-compose-respawn.sh --no-cache    # fresh pull + cache-free build
#
# Optionally implement log stats snapshot before container logs get reset and lost upon container rebuild

set -eu

BASE_DIR="/opt/baton-orchestrator"
. "$BASE_DIR/scripts/tools/helpers/project-network.sh"

NO_CACHE=0
if [ "${1:-}" = "--no-cache" ]; then
    NO_CACHE=1
    shift
fi

# The recreated nginx must join every project network at creation: its
# conf.d names each project's upstream host, and nginx won't start if one
# can't be resolved. Refresh the list from the networks that exist first.
baton_network_write_orchestrator_list

# Tolerated like restart-containers.sh's identical `down` call: a transient
# failure (busy daemon, network-removal race, a stuck container) must not
# abort before `up` runs, or the whole orchestrator stack (nginx, webhook
# listener) stays down until someone notices and reruns this manually.
baton_orchestrator_compose down || {
  echo "WARNING: docker compose down failed for the orchestrator stack (containers may already be stopped)." >&2
}

if [ "$NO_CACHE" -eq 1 ]; then
    echo "[orchestrator-respawn] docker compose pull nginx certbot"
    baton_orchestrator_compose pull nginx certbot
    echo "[orchestrator-respawn] docker compose build --no-cache --pull (webhook)"
    baton_orchestrator_compose build --no-cache --pull
    echo "[orchestrator-respawn] docker compose up -d --force-recreate"
    baton_orchestrator_compose up -d --force-recreate
else
    baton_orchestrator_compose up -d --build --force-recreate
fi
