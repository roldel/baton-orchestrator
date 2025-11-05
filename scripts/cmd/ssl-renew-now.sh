#!/bin/sh
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via 'baton ssl-renew-now'"; exit 1; }
. "$BASE_DIR/env-setup.sh"

docker compose -f "$ORCHESTRATOR_DIR/docker-compose.yml" exec certbot \
  certbot renew --deploy-hook "sh -c 'nginx -s reload || true'" || true

# Also try host-side reload through container if deploy-hook can't run:
docker exec ingress-nginx nginx -s reload 2>/dev/null || true
