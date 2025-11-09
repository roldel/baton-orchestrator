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

ALIASES="$(echo "${DOMAIN_ALIASES:-}" | tr ',' ' ' | xargs || true)"
DOM_ARGS="-d $DOMAIN_NAME"
for h in $ALIASES; do
  DOM_ARGS="$DOM_ARGS -d $h"
done

# === Start certbot container (keeps alive via sleep infinity) ===
echo "[certbot] Starting certbot container (sleep infinity mode)..."
docker compose -f "$COMPOSE_FILE" up -d certbot

# === Issue certificate ===
echo "[certbot] Requesting certificate for: $DOMAIN_NAME ${ALIASES:+($ALIASES)}"
docker compose -f "$COMPOSE_FILE" exec certbot sh -lc \
  "certbot certonly --webroot -w /var/www/acme-challenge \
   $DOM_ARGS --email '$DOMAIN_ADMIN_EMAIL' --agree-tos --no-eff-email --expand"

echo "[certbot] Issuance (or expansion) complete"