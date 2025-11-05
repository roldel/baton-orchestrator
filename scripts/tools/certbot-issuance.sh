#!/bin/sh
# Issue/obtain certs using domain(s) from .env
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via 'baton ssl-issue <project>'"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

proj="${1:-}"
[ -n "$proj" ] || { echo "Usage: baton ssl-issue <project> [--staging] [--email you@domain]"; exit 1; }
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

env_file="$PROJECTS_DIR/$proj/.env"
load_dotenv "$env_file"

domain_args="-d $DOMAIN_NAME"
for d in $DOMAIN_ALIASES; do
  domain_args="$domain_args -d $d"
done

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
