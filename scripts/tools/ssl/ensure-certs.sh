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
# DOMAIN_NAME comes from compute-site-key.sh. Email and aliases are read in a subshell.
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

# --- If cert already exists, its DNS names must match the project ---
if [ -f "$FULLCHAIN" ] && [ -f "$PRIVKEY" ]; then
  echo "[ensure-certs] Existing certificate found for $DOMAIN_NAME in $CERT_DIR"

  if ! command -v openssl >/dev/null 2>&1; then
    echo "[ensure-certs] ERROR: openssl is required to read the existing certificate" >&2
    exit 1
  fi

  if ! SAN="$(openssl x509 -noout -ext subjectAltName -in "$FULLCHAIN")"; then
    echo "[ensure-certs] ERROR: could not read subjectAltName from $FULLCHAIN" >&2
    exit 1
  fi

  . "$BASE_DIR/scripts/tools/helpers/check-domain-aliases.sh"
  if ! ALIASES_NORM="$(baton_normalize_domain_aliases "${DOMAIN_ALIASES:-}")"; then
    exit 1
  fi
  set -- "$DOMAIN_NAME"
  for _alias in $ALIASES_NORM; do
    [ -n "$_alias" ] || continue
    set -- "$@" "$_alias"
  done

  . "$BASE_DIR/scripts/tools/ssl/san-lib.sh"
  if ! baton_san_set_matches "$SAN" "$@"; then
    echo "[ensure-certs] ERROR: certificate SANs do not match DOMAIN_NAME and DOMAIN_ALIASES" >&2
    echo "[ensure-certs]        Reissue with: $BASE_DIR/scripts/tools/ssl/force-reissue-certs.sh $PROJECT" >&2
    exit 1
  fi

  EXPIRY="$(openssl x509 -enddate -noout -in "$FULLCHAIN" | sed 's/^notAfter=//')" || true
  echo "[ensure-certs] Certificate notAfter: ${EXPIRY:-unknown}"
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

# Each name is one certbot -d argument. Reject a leading '-' or a character outside [A-Za-z0-9.-].
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
