# scripts/cmd/deploy.sh
#!/bin/sh
set -eu

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: baton deploy <project>"; exit 1; }

[ -n "${BASE_DIR:-}" ] || { echo "BASE_DIR not set"; exit 1; }
. "$BASE_DIR/env-setup.sh"

# Load all tools
for t in load-dotenv render-server-conf stage-config nginx-test commit-config reload-nginx \
         write-challenge-conf cert-state certbot-issuance ensure-ingress-ready ensure-compose-up; do
  . "$SCRIPT_DIR/tools/${t}.sh"
done

# Load project
env_file="$PROJECTS_DIR/$proj/.env"
[ -f "$env_file" ] || { echo "Missing .env"; exit 1; }
load_dotenv "$env_file"

MAIN_DOMAIN="${DOMAIN_NAME:?}"
ALIASES="${DOMAIN_ALIASES:-}"

echo "Deploying: $proj → $MAIN_DOMAIN $ALIASES"

# Render final config
final_rendered="$(render_conf "$proj" "$MAIN_DOMAIN")"
[ -f "$final_rendered" ] || { echo "Render failed"; exit 1; }

# Start orchestrator if needed
docker compose -f "$ORCHESTRATOR_DIR/docker-compose.yml" up -d

# Check cert state
cert_state="$(sh "$SCRIPT_DIR/tools/cert-state.sh" "$proj" --days 21 || echo "unknown")"
echo "Cert state: $cert_state"

deploy_config() {
  src="$1"; desc="$2"
  echo "$desc"
  tmp="$(stage_config "$src" "$MAIN_DOMAIN")"
  if nginx_test "$tmp"; then
    commit_config "$tmp" "$MAIN_DOMAIN"
    reload_nginx || true
  else
    echo "nginx -t failed → cleaning up"
    rm -f "$tmp"
    return 1
  fi
}

if [ "$cert_state" = "ok" ]; then
  deploy_config "$final_rendered" "Deploying final TLS config..." || exit 1
else
  echo "Issuing certs..."

  # Build domain list
  all_domains="$MAIN_DOMAIN"
  [ -n "$ALIASES" ] && all_domains="$all_domains $ALIASES"

  chall_tmp="$(mktemp)"
  trap 'rm -f "$chall_tmp"' EXIT
  sh "$SCRIPT_DIR/tools/write-challenge-conf.sh" $all_domains > "$chall_tmp"

  echo "Challenge config:"
  cat "$chall_tmp"
  echo

  if sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh" --max-wait 15; then
    deploy_config "$chall_tmp" "Staging challenge config..." || exit 1
  else
    cp "$chall_tmp" "$CONF_DIR/${MAIN_DOMAIN}.conf"
    docker compose -f "$ORCHESTRATOR_DIR/docker-compose.yml" restart ingress-nginx
    sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh" --max-wait 60 || exit 1
  fi

  echo "Running certbot..."
  sh "$SCRIPT_DIR/tools/certbot-issuance.sh" "$proj" || exit 1

  new_state="$(sh "$SCRIPT_DIR/tools/cert-state.sh" "$proj" --days 21)"
  [ "$new_state" = "ok" ] || { echo "Cert issuance failed ($new_state)"; exit 1; }

  deploy_config "$final_rendered" "Deploying final TLS config..." || exit 1
fi

ensure_compose_up "$proj"

echo "DEPLOY SUCCESS"
echo "   $CONF_DIR/${MAIN_DOMAIN}.conf"
echo "   TLS: $MAIN_DOMAIN $ALIASES"