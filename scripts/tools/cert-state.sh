# scripts/tools/cert-state.sh
#!/bin/sh
set -eu

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: $0 <project> [--days N]"; exit 1; }
shift

DAYS=21
while [ $# -gt 0 ]; do
  case "$1" in --days) shift; DAYS="${1:-21}"; esac; shift
done

[ -n "${BASE_DIR:-}" ] || { echo "BASE_DIR not set"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

env_file="$PROJECTS_DIR/$proj/.env"
load_dotenv "$env_file" >/dev/null

DOMAIN="${DOMAIN_NAME:-}"; [ -n "$DOMAIN" ] || { echo "DOMAIN_NAME missing"; exit 1; }
ALIASES="${DOMAIN_ALIASES:-}"

compose="docker compose -f $ORCHESTRATOR_DIR/docker-compose.yml"

# === ENSURE certbot container is running ===
if ! $compose ps certbot | grep -q "Up"; then
  echo "Starting certbot container..."
  $compose up -d certbot
  sleep 2
fi

# === Helper commands inside certbot container ===
exists() { $compose exec -T certbot test -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem"; }
not_expiring() {
  secs=$((DAYS * 86400))
  $compose exec -T certbot openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -checkend "$secs"
}
get_sans() {
  $compose exec -T certbot openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -text \
    | awk '/DNS:/{gsub(/DNS:/, ""); print}' | tr -d ' ,'
}

if ! exists; then echo "missing"; exit 2; fi
if ! not_expiring; then echo "expiring_soon"; exit 3; fi

if [ -n "$ALIASES" ]; then
  sans="$(get_sans)"
  for name in $DOMAIN $ALIASES; do
    echo "$sans" | grep -Fx "$name" > /dev/null || { echo "sans_missing:$name"; exit 4; }
  done
fi

echo "ok"
exit 0