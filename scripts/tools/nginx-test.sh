#!/bin/sh
# Run nginx -t inside the ingress container and fail if config invalid.
# Usage: nginx_test <host_tmp_conf_path>
set -eu

nginx_test() {
  local host_tmp_conf="$1"

  [ -f "$host_tmp_conf" ] || { echo "nginx_test: file not found: $host_tmp_conf" >&2; return 1; }

  . "$SCRIPT_DIR/tools/ensure-ingress-ready.sh"
  sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh"

  local ingress="${INGRESS_NAME:-ingress-nginx}"
  local tmp_base="$(basename "$host_tmp_conf")"
  local tmp_in_container="${CONF_DEST_IN_CONTAINER:-/etc/nginx/conf.d}/$tmp_base"

  echo "Testing config: $host_tmp_conf"

  # Double-check visibility before testing
  if ! docker exec "$ingress" sh -c "test -f '$tmp_in_container'"; then
    echo "ERROR: File not visible in container as $tmp_in_container" >&2
    docker inspect -f '{{range .Mounts}}{{printf "%s -> %s\n" .Source .Destination}}{{end}}' "$ingress" || true
    return 1
  fi

  # Quiet test (-t -q), but print any errors
  if ! docker exec "$ingress" sh -c "nginx -t -q"; then
    echo "nginx -t failed. Showing last 50 lines of error log (if available):"
    docker exec "$ingress" sh -c "tail -n 50 /var/log/nginx/error.log 2>/dev/null || true"
    return 1
  fi
  echo "nginx -t PASSED"
}

# If invoked directly
if [ "${1:-}" = "--selftest" ]; then
  echo "Selftest not implemented"; exit 0
fi
