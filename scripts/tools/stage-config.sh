#!/bin/sh
# Stage a rendered nginx server config into the shared conf.d directory that the
# ingress-nginx container mounts; return the temp path on stdout.
#
# Usage: stage_config <rendered_path> <domain>
#
# Requires env:
# - CONF_DIR (host path bind-mounted into /etc/nginx/conf.d)
# - Ingress container name: INGRESS_NAME (default ingress-nginx)

set -eu

stage_config() {
  local rendered="$1"
  local domain="$2"

  [ -f "$rendered" ] || { echo "Rendered file not found: $rendered" >&2; return 1; }
  [ -n "${CONF_DIR:-}" ] || { echo "CONF_DIR not set"; return 1; }

  local tmp_name=".$domain.conf.tmp.$$"
  local dest_host="$CONF_DIR/$tmp_name"
  cp "$rendered" "$dest_host"

  echo "Staged → $dest_host"

  # Ensure ingress is ready and the file is visible in the container
  . "$SCRIPT_DIR/tools/ensure-ingress-ready.sh"
  sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh"

  local ingress="${INGRESS_NAME:-ingress-nginx}"
  local dest_in_container="${CONF_DEST_IN_CONTAINER:-/etc/nginx/conf.d}/$tmp_name"

  # Retry a few times in case the mount settles slowly
  for i in $(seq 1 10); do
    if docker exec "$ingress" sh -c "test -f '$dest_in_container'"; then
      break
    fi
    sleep 1
  done

  if ! docker exec "$ingress" sh -c "test -f '$dest_in_container'"; then
    echo "ERROR: File not visible in container as $dest_in_container" >&2
    echo "Mounts:"
    docker inspect -f '{{range .Mounts}}{{printf "%s -> %s\n" .Source .Destination}}{{end}}' "$ingress" || true
    return 1
  fi

  # Output host path (deploy.sh uses this)
  printf "%s\n" "$dest_host"
}

# If invoked directly
if [ "${1:-}" = "--selftest" ]; then
  echo "Selftest not implemented"; exit 0
fi
