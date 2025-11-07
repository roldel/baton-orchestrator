#!/bin/sh
# scripts/cmd/deploy.sh
# Robust deploy: handles missing/expiring/SAN-missing certs + aliases
set -eu

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: baton deploy <project>"; exit 1; }

[ -n "${BASE_DIR:-}" ] || { echo "BASE_DIR not set – run via 'baton'"; exit 1; }
. "$BASE_DIR/env-setup.sh"

# ----------------------------------------------------------------------
# Load helpers
# ----------------------------------------------------------------------
for tool in \
  load-dotenv.sh render-server-conf.sh stage-config.sh nginx-test.sh \
  commit-config.sh reload-nginx.sh write-challenge-conf.sh \
  cert-state.sh certbot-issuance.sh ensure-ingress-ready.sh ensure-compose-up.sh
do
  . "$SCRIPT_DIR/tools/$tool"
done

# ----------------------------------------------------------------------
# Load project .env
# ----------------------------------------------------------------------
env_file="$PROJECTS_DIR/$proj/.env"
[ -f "$env_file" ] || { echo "Missing .env: $env_file"; exit 1; }
load_dotenv "$env_file" >/dev/null

MAIN_DOMAIN="${DOMAIN_NAME:?DOMAIN_NAME missing in $env_file}"
ALIASES="${DOMAIN_ALIASES:-}"

echo "==> Deploying project: $proj"
echo "    Domain : $MAIN_DOMAIN"
[ -n "$ALIASES" ] && echo "    Aliases: $ALIASES"

# ----------------------------------------------------------------------
# 1. Render final server config (once)
# ----------------------------------------------------------------------
echo "Rendering final server config..."
final_rendered="$(render_conf "$proj" "$MAIN_DOMAIN")"
[ -f "$final_rendered" ] || { echo "Render failed"; exit 1; }

# ----------------------------------------------------------------------
# 2. Check certificate state
# ----------------------------------------------------------------------
cert_state="$(sh "$SCRIPT_DIR/tools/cert-state.sh" "$proj" --days 21 || echo "unknown")"
echo "Certificate state: $cert_state"

# ----------------------------------------------------------------------
# Helper: stage → test → commit (atomic)
# ----------------------------------------------------------------------
deploy_config() {
  local src="$1" desc="$2"
  echo "$desc"
  tmp="$(stage_config "$src" "$MAIN_DOMAIN")"
  echo "Testing with nginx -t..."
  if nginx_test "$tmp"; then
    commit_config "$tmp" "$MAIN_DOMAIN"
    reload_nginx || true
    return 0
  else
    echo "ERROR: nginx -t failed – cleaning up"
    rm -f "$tmp"
    return 1
  fi
}

# ----------------------------------------------------------------------
# FAST PATH: certs OK
# ----------------------------------------------------------------------
if [ "$cert_state" = "ok" ]; then
  echo "Certs valid → deploying final TLS config"
  deploy_config "$final_rendered" "Deploying final TLS config..." || exit 1

# ----------------------------------------------------------------------
# SLOW PATH: need certs
# ----------------------------------------------------------------------
else
  echo "Certs invalid ($cert_state) → issuing via challenge"

  # Build challenge config with ALL domains (main + aliases)
  chall_tmp="$(mktemp)"
  trap 'rm -f "$chall_tmp"' EXIT

  # Build space-separated domain list
  all_domains="$MAIN_DOMAIN"
  [ -n "$ALIASES" ] && all_domains="$all_domains $ALIASES"

  echo "Generating challenge config for: $all_domains"
  sh "$SCRIPT_DIR/tools/write-challenge-conf.sh" $all_domains > "$chall_tmp"

  # Show what was generated
  echo "Challenge config:"
  cat "$chall_tmp"
  echo

  # Stage challenge config
  if sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh" --max-wait 15; then
    deploy_config "$chall_tmp" "Staging challenge-only config..." || exit 1
  else
    echo "Ingress down → forcing challenge config"
    cp "$chall_tmp" "$CONF_DIR/${MAIN_DOMAIN}.conf"
    docker compose -f "$ORCHESTRATOR_DIR/docker-compose.yml" restart ingress-nginx >/dev/null
    sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh" --max-wait 60 || exit 1
  fi

  # Issue certs
  echo "Requesting certificate for: $MAIN_DOMAIN + aliases"
  sh "$SCRIPT_DIR/tools/certbot-issuance.sh" "$proj" || {
    echo "Certbot failed – keeping challenge config"
    exit 1
  }

  # Verify
  new_state="$(sh "$SCRIPT_DIR/tools/cert-state.sh" "$proj" --days 21 || echo "unknown")"
  [ "$new_state" = "ok" ] || { echo "ERROR: certs still not OK ($new_state)"; exit 1; }

  # Deploy final
  echo "Certs issued → deploying final TLS config"
  deploy_config "$final_rendered" "Deploying final TLS config..." || exit 1
fi

# ----------------------------------------------------------------------
# 3. Start app stack
# ----------------------------------------------------------------------
echo "Starting application stack..."
ensure_compose_up "$proj"

echo
echo "DEPLOY COMPLETE"
echo "   Config: $CONF_DIR/${MAIN_DOMAIN}.conf"
echo "   TLS: Ready (covers: $MAIN_DOMAIN $ALIASES)"