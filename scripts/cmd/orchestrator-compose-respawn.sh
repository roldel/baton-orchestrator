#!/bin/sh
# scripts/cmd/orchestrator-compose-respawn.sh
# Full respawn of the orchestrator stack itself (nginx, webhook listener, etc).
#
# Optionally implement log stats snapshot before container logs get reset and lost upon container rebuild

set -eu

BASE_DIR="/opt/baton-orchestrator"
. "$BASE_DIR/scripts/tools/helpers/project-network.sh"

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
baton_orchestrator_compose up -d --build --force-recreate
