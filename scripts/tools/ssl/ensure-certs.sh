#!/bin/sh
# Ensure a Let's Encrypt certificate exists for the project's DOMAIN_NAME
# Uses certbot via docker compose (webroot mode, ACME handled by nginx)

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"
ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"

echo "[ensure-certs] Ensuring certificates for project: $PROJECT (dir: $PROJECT_DIR)"

# --- Basic validation ---
if [ ! -d "$PROJECT_DIR" ]; then
  echo "[ensure-certs] ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "[ensure-certs] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

if [ ! -f "$ORCHESTRATOR_COMPOSE" ]; then
  echo "[ensure-certs] ERROR: Orchestrator compose file not found: $ORCHESTRATOR_COMPOSE" >&2
  exit 1
fi

# --- Load env vars ---
# shellcheck source=/dev/null
. "$ENV_FILE"

if [ -z "${DOMAIN_NAME:-}" ]; then
  echo "[ensure-certs] ERROR: DOMAIN_NAME must be set in .env" >&2
  exit 1
fi

if [ -z "${DOMAIN_ADMIN_EMAIL:-}" ]; then
  echo "[ensure-certs] ERROR: DOMAIN_ADMIN_EMAIL must be set in .env (for Let's Encrypt registration)" >&2
  exit 1
fi

CERT_DIR="/etc/letsencrypt/live/$DOMAIN_NAME"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"

# --- If cert already exists, log and exit OK ---
if [ -f "$FULLCHAIN" ] && [ -f "$PRIVKEY" ]; then
  echo "[ensure-certs] Existing certificate found for $DOMAIN_NAME in $CERT_DIR"

  if command -v openssl >/dev/null 2>&1; then
    EXPIRY="$(openssl x509 -enddate -noout -in "$FULLCHAIN" 2>/dev/null | sed 's/^notAfter=//')"
    echo "[ensure-certs] Certificate notAfter: $EXPIRY"
  else
    echo "[ensure-certs] Note: openssl not available, skipping expiry check."
  fi

  # For now we only ensure presence; renewal logic can be added later.
  exit 0
fi

echo "[ensure-certs] No existing certificate for $DOMAIN_NAME. Requesting a new one..."

# --- Build domain list for certbot: primary + aliases ---
ALL_DOMAINS="$DOMAIN_NAME"

if [ -n "${DOMAIN_ALIASES:-}" ]; then
  # DOMAIN_ALIASES can be comma- or space-separated → normalize to spaces
  ALIASES_CLEAN="$(printf '%s\n' "$DOMAIN_ALIASES" | tr ',' ' ')"
  ALL_DOMAINS="$ALL_DOMAINS $ALIASES_CLEAN"
fi

DOMAIN_ARGS=""
for d in $ALL_DOMAINS; do
  DOMAIN_ARGS="$DOMAIN_ARGS -d $d"
done

echo "[ensure-certs] Using domains:$DOMAIN_ARGS"
echo "[ensure-certs] Running certbot via docker compose (webroot mode)..."

# --- Invoke certbot container via docker compose ---
docker compose -f "$ORCHESTRATOR_COMPOSE" run --rm certbot certonly \
  --webroot -w /var/www/acme-challenge \
  $DOMAIN_ARGS \
  --email "$DOMAIN_ADMIN_EMAIL" \
  --agree-tos \
  --non-interactive

echo "[ensure-certs] Certbot run completed for $DOMAIN_NAME"
