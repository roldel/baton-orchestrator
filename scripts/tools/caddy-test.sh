#!/bin/sh
# scripts/tools/caddy-test.sh
set -eu

caddy_test() {
  tmp_file="$1"

  # Dry-run config validation
  if ! docker exec ingress-caddy caddy validate --config "$tmp_file" >/dev/null 2>&1; then
    echo "ERROR: Caddy config validation failed:" >&2
    docker exec ingress-caddy caddy validate --config "$tmp_file" >&2 || true
    rm -f "$tmp_file"
    exit 1
  fi

  echo "Caddy config syntax OK"
}