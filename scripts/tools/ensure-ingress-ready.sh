#!/bin/sh
# Wait until the ingress-nginx container is running and its config dir is accessible.
# Usage: ensure-ingress-ready.sh
set -eu

INGRESS_NAME="${INGRESS_NAME:-ingress-nginx}"
CONF_DEST_IN_CONTAINER="${CONF_DEST_IN_CONTAINER:-/etc/nginx/conf.d}"

# Wait for container to be "running"
echo "Waiting for $INGRESS_NAME to be running..."
for i in $(seq 1 60); do
  state="$(docker inspect -f '{{.State.Status}}' "$INGRESS_NAME" 2>/dev/null || echo 'none')"
  if [ "$state" = "running" ]; then
    break
  fi
  if [ "$state" = "restarting" ]; then
    # Show last few log lines to aid debugging
    docker logs --tail 20 "$INGRESS_NAME" || true
  fi
  sleep 1
done

state="$(docker inspect -f '{{.State.Status}}' "$INGRESS_NAME" 2>/dev/null || echo 'none')"
[ "$state" = "running" ] || { echo "ERROR: $INGRESS_NAME is not running (state: $state)"; exit 1; }

# Ensure the conf.d directory is accessible inside the container
for i in $(seq 1 30); do
  if docker exec "$INGRESS_NAME" sh -c "test -d '$CONF_DEST_IN_CONTAINER'"; then
    break
  fi
  sleep 1
done

if ! docker exec "$INGRESS_NAME" sh -c "test -d '$CONF_DEST_IN_CONTAINER'"; then
  echo "ERROR: $CONF_DEST_IN_CONTAINER not found inside $INGRESS_NAME."
  echo "Mounts:"
  docker inspect -f '{{range .Mounts}}{{printf "%s -> %s\n" .Source .Destination}}{{end}}' "$INGRESS_NAME" || true
  exit 1
fi
