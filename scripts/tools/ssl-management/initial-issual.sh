#!/bin/sh
# Issue/expand a cert for DOMAIN_NAME (+ aliases) using a ONE-SHOT, NON-INTERACTIVE certbot
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
COMPOSE_FILE="$ROOT/orchestrator/docker-compose.yml"
. "$ROOT/env-setup.sh"

ENV_FILE="$PROJECTS_DIR/$PROJECT/.env"
[ -r "$ENV_FILE" ] || { echo "ERROR: Cannot read $ENV_FILE" >&2; exit 1; }

set -a
. "$ENV_FILE"
set +a

[ -n "${DOMAIN_NAME:-}" ] || { echo "ERROR: DOMAIN_NAME missing in $ENV_FILE" >&2; exit 1; }
[ -n "${DOMAIN_ADMIN_EMAIL:-}" ] || { echo "ERROR: DOMAIN_ADMIN_EMAIL missing in $ENV_FILE" >&2; exit 1; }

if ! printf '%s' "$DOMAIN_ADMIN_EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; then
  echo "ERROR: DOMAIN_ADMIN_EMAIL invalid: '$DOMAIN_ADMIN_EMAIL'" >&2
  exit 1
fi

ALIASES="$(echo "${DOMAIN_ALIASES:-}" | tr ',' ' ' | xargs || true)"
DOM_ARGS="-d $DOMAIN_NAME"
for h in $ALIASES; do
  DOM_ARGS="$DOM_ARGS -d $h"
done

echo "[certbot] Issuing certificate (non-interactive) for: $DOMAIN_NAME ${ALIASES:+($ALIASES)}"

# ONE-SHOT + NON-INTERACTIVE
docker compose -f "$COMPOSE_FILE" run --rm certbot \
  certonly --webroot -w /var/www/acme-challenge \
  --non-interactive \
  --agree-tos \
  --email "$DOMAIN_ADMIN_EMAIL" \
  --no-eff-email \
  $DOM_ARGS

# Verify files landed
LIVE_DIR="$CERTS_DIR/live/$DOMAIN_NAME"
FULLCHAIN="$LIVE_DIR/fullchain.pem"

for i in $(seq 1 10); do
  if [ -f "$FULLCHAIN" ]; then
    echo "[certbot] Certificate confirmed: $FULLCHAIN"
    break
  fi
  echo "[certbot] Waiting for cert files... ($i/10)"
  sleep 1
done

[ -f "$FULLCHAIN" ] || { echo "ERROR: Certificate missing after issuance!" >&2; exit 1; }

echo "[certbot] Issuance complete and verified"