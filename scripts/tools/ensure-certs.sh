#!/bin/sh
# Ensure a valid Let's Encrypt certificate exists for DOMAIN_NAME (+ DOMAIN_ALIASES).
# If missing/expiring or SANs don't match, temporarily swap in a challenge-only
# nginx config, issue/renew via certbot (webroot), then restore the final config.
#
# Usage:
#   ensure-certs.sh <project> [--days 21] [--staging] [--email you@domain]
#
# Requirements:
# - env-setup.sh defines: BASE_DIR, SCRIPT_DIR, PROJECTS_DIR, ORCHESTRATOR_DIR, CONF_DIR, CERTS_DIR
# - load-dotenv.sh provides: load_dotenv <envfile>
# - render-server-conf.sh exports: render_conf <project> <domain> -> rendered file path
# - stage-config.sh exports: stage_config <rendered_path> <domain> -> temp conf path
# - nginx-test.sh exports: nginx_test <conf_path>
# - commit-config.sh exports: commit_config <conf_path> <domain>
# - certbot-issuance.sh handles issuance/renewal using --webroot

set -eu

# --- common env
[ -n "${BASE_DIR:-}" ] || { echo "This script is intended to run via your baton entrypoint (BASE_DIR unset)."; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: ensure-certs.sh <project> [--days 21] [--staging] [--email you@domain]"; exit 1; }
shift || true

DAYS=21
STAGING=0
EMAIL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --days) shift; DAYS="${1:-21}" ;;
    --staging) STAGING=1 ;;
    --email) shift; EMAIL="${1:-}" ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
  shift || true
done

env_file="$PROJECTS_DIR/$proj/.env"
[ -f "$env_file" ] || { echo "Missing env for project: $env_file"; exit 1; }
load_dotenv "$env_file" >/dev/null

DOMAIN="${DOMAIN_NAME:-}"
ALIASES="${DOMAIN_ALIASES:-}"
[ -n "$DOMAIN" ] || { echo "DOMAIN_NAME missing in $env_file"; exit 1; }

compose="-f $ORCHESTRATOR_DIR/docker-compose.yml"
need_issue=0

# Helpers that run inside the certbot container
check_exists() {
  docker compose $compose exec -T certbot sh -c "[ -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]"
}
check_not_expiring() {
  # true (0) if NOT expiring within the given seconds
  secs=$(( DAYS * 24 * 3600 ))
  docker compose $compose exec -T certbot openssl x509 \
    -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
    -noout -checkend "$secs" >/dev/null 2>&1
}
current_sans() {
  docker compose $compose exec -T certbot sh -c "
    openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -noout -text \
      | awk '/Subject Alternative Name/{flag=1;next} /X509v3/{flag=0} flag' \
      | tr ',' '\n' | sed 's/^[[:space:]]*//'
  " | sed 's/^DNS://'
}

# nginx reload (best-effort)
reload_nginx() {
  # Wrapper allows this script to work even if the helper isn't present
  if [ -x "$SCRIPT_DIR/tools/reload-nginx.sh" ]; then
    "$SCRIPT_DIR/tools/reload-nginx.sh" || true
  else
    docker exec ingress-nginx nginx -s reload 2>/dev/null || true
  fi
}

echo "🔐 Ensuring certificates for: $DOMAIN${ALIASES:+ ($ALIASES)}"

if ! check_exists; then
  echo "• No existing certificate found for $DOMAIN"
  need_issue=1
else
  echo "• Existing certificate present"
  if ! check_not_expiring; then
    echo "• Certificate expires within $DAYS day(s) → renewal required"
    need_issue=1
  else
    echo "• Certificate is not expiring within $DAYS day(s)"
    if [ -n "$ALIASES" ]; then
      sans="$(current_sans | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      echo "• Current SANs: $sans"
      for name in $DOMAIN $ALIASES; do
        echo "$sans" | grep -qw "$name" || { echo "• Missing SAN: $name"; need_issue=1; }
      done
    fi
  fi
fi

ISSUE_FLAGS=""
[ "$STAGING" -eq 1 ] && ISSUE_FLAGS="$ISSUE_FLAGS --staging"
[ -n "$EMAIL" ] && ISSUE_FLAGS="$ISSUE_FLAGS --email $EMAIL"

challenge_conf="$CONF_DIR/${DOMAIN}.conf" # we will overwrite this with the challenge-only server
write_challenge_conf() {
  tmp="$CONF_DIR/.${DOMAIN}.challenge.$$"
  cat >"$tmp" <<EOF
# Temporary ACME challenge-only server for $DOMAIN
server {
  listen 80;
  listen [::]:80;
  server_name $DOMAIN ${ALIASES:-};

  location /.well-known/acme-challenge/ {
    root /var/www/certbot;
  }
  # IMPORTANT: no HTTPS redirect here; keep port 80 reachable for HTTP-01
}
EOF
  mv "$tmp" "$challenge_conf"
}

if [ "$need_issue" -eq 1 ]; then
  echo "⚙️  Remediation: challenge-only config → issue/renew → restore final config"

  # 1) Activate the challenge-only config
  write_challenge_conf
  echo "• Challenge config activated at: $challenge_conf"
  reload_nginx

  # 2) Issue/Renew via your existing script (webroot flow)
  echo "• Running certbot issuance..."
  if [ -n "$ISSUE_FLAGS" ]; then
    sh "$SCRIPT_DIR/tools/certbot-issuance.sh" "$proj" $ISSUE_FLAGS
  else
    sh "$SCRIPT_DIR/tools/certbot-issuance.sh" "$proj"
  fi

  # 3) Re-render, test, and commit the real site config
  . "$SCRIPT_DIR/tools/render-server-conf.sh"
  rendered_path="$(render_conf "$proj" "$DOMAIN")"

  . "$SCRIPT_DIR/tools/stage-config.sh"
  tmp_conf="$(stage_config "$rendered_path" "$DOMAIN")"

  . "$SCRIPT_DIR/tools/nginx-test.sh"
  nginx_test "$tmp_conf" && echo "• nginx -t PASSED"

  . "$SCRIPT_DIR/tools/commit-config.sh"
  commit_config "$tmp_conf" "$DOMAIN"

  # 4) Reload Nginx
  reload_nginx
  echo "✅ Certificates ensured & final config restored"
else
  echo "✅ Certificates already valid; no changes made"
fi
