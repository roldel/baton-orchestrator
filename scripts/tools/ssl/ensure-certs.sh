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
# Read in isolated subshells via load_env_safe, not sourced directly (see
# that file's header): ORCHESTRATOR_COMPOSE is reused below to invoke
# `docker compose`, and a project's own .env sourced directly could both
# execute arbitrary commands immediately (e.g. a value containing `;`) and,
# even if that were somehow survived, redefine ORCHESTRATOR_COMPOSE to point
# `docker compose -f` at an attacker-authored compose file.
# DOMAIN_NAME specifically is resolved via compute-site-key.sh rather than
# extracted raw: it builds CERT_DIR below (and is passed to certbot), so
# without compute-site-key.sh's path-traversal/character validation a
# crafted DOMAIN_NAME could point certificate checks at an arbitrary path.
LOAD_ENV_SAFE_SH="$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
DOMAIN_NAME="$(sh "$BASE_DIR/scripts/tools/helpers/compute-site-key.sh" "$PROJECT")"
DOMAIN_ADMIN_EMAIL="$(
  set +eu
  . "$LOAD_ENV_SAFE_SH"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${DOMAIN_ADMIN_EMAIL:-}"
  fi
)"
DOMAIN_ALIASES="$(
  set +eu
  . "$LOAD_ENV_SAFE_SH"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${DOMAIN_ALIASES:-}"
  fi
)"

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

# Each entry becomes a separate `-d <entry>` certbot argument below.
# DOMAIN_ALIASES comes straight from the project's own .env with no
# character validation (unlike render-server-conf.sh, which validates it
# before substituting into nginx config) — and compute-site-key.sh's check
# on DOMAIN_NAME constrains the character set but not a leading '-'. Without
# this check, an entry such as "-d evil.com --manual-auth-hook /path" (or
# simply a value starting with '-') would be parsed by certbot as extra
# flags rather than a plain domain argument.
for d in $ALL_DOMAINS; do
  case "$d" in
    -*)
      echo "[ensure-certs] ERROR: domain entry '$d' cannot start with '-' (would be parsed as a certbot flag)" >&2
      exit 1
      ;;
    *[!A-Za-z0-9.-]*)
      echo "[ensure-certs] ERROR: domain entry '$d' contains characters unsafe for a certbot argument (only letters, digits, '.', '-' are allowed)" >&2
      exit 1
      ;;
  esac
done

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
