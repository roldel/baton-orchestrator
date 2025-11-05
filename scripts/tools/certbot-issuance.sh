#!/bin/sh
set -eu
. "$(dirname "$0")/../env-setup.sh"

proj="${1:?Usage: certbot-issuance.sh <project> [--staging] [--email you@domain] }"
shift || true

STAGING=0
EMAIL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --staging) STAGING=1 ;;
    --email) shift; EMAIL="${1:-}";;
  esac
  shift || true
done

eval "$("$SCRIPT_DIR/tools/domain-name-aliases-retriever.sh" "$PROJECTS_DIR/$proj/server.conf")"
domain_args=""
for d in "$MAIN_DOMAIN_NAME" $DOMAIN_ALIASES; do
  [ -n "$d" ] && domain_args="$domain_args -d $d"
done

[ -n "$domain_args" ] || { echo "No domains parsed"; exit 1; }

staging_flag=""
[ "$STAGING" -eq 1 ] && staging_flag="--staging"

email_args=""
if [ -n "$EMAIL" ]; then
  email_args="--email $EMAIL --agree-tos"
else
  email_args="--register-unsafely-without-email"
fi

docker compose -f "$ORCHESTRATOR_DIR/docker-compose.yml" exec certbot \
  certbot certonly --non-interactive $staging_flag $email_args \
  --webroot -w /var/www/certbot $domain_args
