#!/bin/sh
# Determine the certificate state for DOMAIN_NAME (+ DOMAIN_ALIASES).
# Exit codes:
#   0 = OK (exists, not expiring soon, SANs cover all names)
#   2 = missing
#   3 = expiring soon (<= DAYS)
#   4 = SAN mismatch
# Prints a brief reason to stdout.

set -eu

[ -n "${BASE_DIR:-}" ] || { echo "BASE_DIR not set"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: cert-state.sh <project> [--days 21]"; exit 1; }
shift || true

DAYS=21
while [ $# -gt 0 ]; do
  case "$1" in
    --days) shift; DAYS="${1:-21}" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift || true
done

env_file="$PROJECTS_DIR/$proj/.env"
load_dotenv "$env_file" >/dev/null

DOMAIN="${DOMAIN_NAME:-}"
ALIASES="${DOMAIN_ALIASES:-}"
[ -n "$DOMAIN" ] || { echo "DOMAIN_NAME missing in $env_file"; exit 1; }

compose="-f $ORCHESTRATOR_DIR/docker-compose.yml"

exists() {
  docker compose $compose exec -T certbot sh -c "[ -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]"
}

not_expiring() {
  secs=$(( DAYS * 24 * 3600 ))
  docker compose $compose exec -T certbot openssl x509 \
    -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
    -noout -checkend "$secs" >/dev/null 2>&1
}

get_sans() {
  docker compose $compose exec -T certbot sh -c "
    openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -noout -text \
      | awk '/Subject Alternative Name/{flag=1;next} /X509v3/{flag=0} flag' \
      | tr ',' '\n' | sed 's/^[[:space:]]*//'
  " | sed 's/^DNS://'
}

if ! exists; then
  echo "missing"
  exit 2
fi

if ! not_expiring; then
  echo "expiring_soon"
  exit 3
fi

# Check SAN coverage
if [ -n "$ALIASES" ]; then
  sans="$(get_sans | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  for name in $DOMAIN $ALIASES; do
    echo "$sans" | grep -qw "$name" || { echo "sans_missing:$name"; exit 4; }
  done
fi

echo "ok"
exit 0
