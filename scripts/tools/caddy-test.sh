#!/bin/sh
# scripts/tools/caddy-test.sh
set -eu

caddy_test() {
  tmp_file_host_path="$1"
  tmp_file_basename=$(basename "$tmp_file_host_path")
  tmp_file_container_path="/etc/caddy/conf.d/$tmp_file_basename"

  echo "Validating staged config inside Caddy container..."
  if ! docker exec ingress-caddy caddy validate --config "$tmp_file_container_path" --adapter caddyfile >/dev/null 2>&1; then
    echo "ERROR: Caddy config validation failed:" >&2
    docker exec ingress-caddy caddy validate --config "$tmp_file_container_path" --adapter caddyfile >&2
    rm -f "$tmp_file_host_path"
    exit 1
  fi

  echo "Caddy config syntax OK"
}
