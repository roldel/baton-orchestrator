#!/bin/sh
# Issue/expand a cert for DOMAIN_NAME (+ aliases) using the running certbot container (webroot)
# Usage: initial-issual.sh <project-name>
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
COMPOSE_FILE="$ROOT/orchestrator/docker-compose.yml"
# shellcheck disable=SC1091
. "$ROOT/env-setup.sh"

ENV_FILE="$PROJECTS_DIR/$PROJECT/.env"
[ -r "$ENV_FILE" ] || { echo "ERROR: Cannot read $ENV_FILE" >&2; exit 1; }

# Load env
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

[ -n "${DOMAIN_NAME:-}" ] || { echo "ERROR: DOMAIN_NAME missing in $ENV_FILE" >&2; exit 1; }
[ -n "${DOMAIN_ADMIN_EMAIL:-}" ] || { echo "ERROR: DOMAIN_ADMIN_EMAIL missing in $ENV_FILE (mandatory)" >&2; exit 1; }

# Basic email sanity
if ! printf '%s' "$DOMAIN_ADMIN_EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; then
  echo "ERROR: DOMAIN_ADMIN_EMAIL looks invalid: '$DOMAIN_ADMIN_EMAIL'" >&2
  exit 1
fi

# Build domain arguments
ALIASES="$(echo "${DOMAIN_ALIASES:-}" | tr ',' ' ' | xargs || true)"
DOM_ARGS="-d $DOMAIN_NAME"
for h in $ALIASES; do
  DOM_ARGS="$DOM_ARGS -d $h"
done

echo "[certbot] Domains: $DOMAIN_NAME ${ALIASES:+($ALIASES)}"

# === Start certbot container ===
echo "[certbot] Starting certbot container..."
docker compose -f "$COMPOSE_FILE" up -d certbot

# === Wait for certbot to be ready ===
echo "[certbot] Waiting for certbot container to be ready..."
for i in $(seq 1 30); do
  if docker compose -f "$COMPOSE_FILE" ps certbot | grep -q "Up"; then
    echo "[certbot] Container ready after $i seconds"
    break
  fi
  sleep 1
done

# === Test ACME challenge endpoint ===
echo "[certbot] Testing ACME challenge endpoint..."
if ! curl -s -f -m 10 "http://$DOMAIN_NAME/.well-known/acme-challenge/test" >/dev/null 2>&1; then
  echo "WARNING: ACME challenge endpoint not reachable. Check:"
  echo "  - DNS A record for $DOMAIN_NAME"
  echo "  - Port 80 open on host"
  echo "  - Nginx logs: docker logs ingress-nginx"
  echo "Continuing anyway..."
fi

# === Try staging first (dry-run) ===
echo "[certbot] Testing with staging environment (dry-run)..."
STAGING_CMD="
set -e
echo '=== CERTBOT STAGING TEST ==='
certbot certonly \\
  --webroot -w /var/www/acme-challenge \\
  $DOM_ARGS \\
  --email '$DOMAIN_ADMIN_EMAIL' \\
  --agree-tos \\
  --no-eff-email \\
  --expand \\
  --dry-run \\
  --non-interactive \\
  --verbose
"

if ! docker compose -f "$COMPOSE_FILE" exec certbot sh -c "$STAGING_CMD" 2>&1 | tee /tmp/certbot-staging.log; then
  echo "❌ STAGING FAILED. Check /tmp/certbot-staging.log for details."
  echo "Common issues:"
  echo "  - DNS not propagated: dig $DOMAIN_NAME"
  echo "  - Port 80 blocked: curl -I http://$DOMAIN_NAME/health"
  exit 1
fi

echo "✅ STAGING PASSED. Proceeding to production certificate..."

# === Issue production certificate ===
echo "[certbot] Issuing production certificate..."
PROD_CMD="
set -e
echo '=== CERTBOT PRODUCTION ==='
certbot certonly \\
  --webroot -w /var/www/acme-challenge \\
  $DOM_ARGS \\
  --email '$DOMAIN_ADMIN_EMAIL' \\
  --agree-tos \\
  --no-eff-email \\
  --expand \\
  --non-interactive \\
  --verbose
"

if docker compose -f "$COMPOSE_FILE" exec certbot sh -c "$PROD_CMD" 2>&1 | tee /tmp/certbot-prod.log; then
  echo "[certbot] ✅ Issuance complete!"
  echo "[certbot] Certificate saved: $CERTS_DIR/live/$DOMAIN_NAME/"
  
  # Verify certificate
  if [ -f "$CERTS_DIR/live/$DOMAIN_NAME/fullchain.pem" ]; then
    echo "[certbot] ✅ Certificate file verified"
  else
    echo "❌ Certificate file missing after successful issuance!"
    exit 1
  fi
else
  echo "❌ PRODUCTION FAILED. Check /tmp/certbot-prod.log"
  exit 1
fi

echo "[certbot] 🎉 Certificate issuance successful!"