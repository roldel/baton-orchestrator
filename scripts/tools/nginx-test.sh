#!/bin/sh
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via baton"; exit 1; }
. "$BASE_DIR/env-setup.sh"

nginx_test() {
  host_conf="$1"
  echo "Testing config: $host_conf"

  case "$host_conf" in
    "$CONF_DIR"/*) container_conf="/etc/nginx/conf.d/${host_conf#$CONF_DIR/}" ;;
    *) echo "ERROR: $host_conf is not under $CONF_DIR" >&2; return 1 ;;
  esac

  if ! docker exec ingress-nginx test -f "$container_conf"; then
    echo "ERROR: File not visible in container as $container_conf" >&2
    return 1
  fi

  if ! docker exec ingress-nginx nginx -t >/dev/null 2>&1; then
    echo "nginx -t failed:" >&2
    docker exec ingress-nginx nginx -t >&2
    return 1
  fi

  echo "Config valid"
  return 0
}
