#!/bin/sh
# Deploy a project with safe cert pre-checks.
# 1) If certs missing/invalid -> deploy challenge-only HTTP config, issue certs.
# 2) Deploy final TLS config and test.
set -eu

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: deploy.sh <project>"; exit 1; }

[ -n "${BASE_DIR:-}" ] || { echo "BASE_DIR not set"; exit 1; }
. "$BASE_DIR/env-setup.sh"

. "$SCRIPT_DIR/tools/load-dotenv.sh"
env_file="$PROJECTS_DIR/$proj/.env"
[ -f "$env_file" ] || { echo "Missing env for project: $env_file"; exit 1; }
load_dotenv "$env_file" >/dev/null

MAIN_DOMAIN="${DOMAIN_NAME:-}"
ALIASES="${DOMAIN_ALIASES:-}"
[ -n "$MAIN_DOMAIN" ] || { echo "DOMAIN_NAME missing in $env_file"; exit 1; }

echo "==> Deploying project: $proj"
echo "    Domain: $MAIN_DOMAIN"
[ -n "$ALIASES" ] && echo "    Aliases: $ALIASES"

# Ensure ingress is up & conf dir is mounted
. "$SCRIPT_DIR/tools/ensure-ingress-ready.sh"
sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh"

# ---- Phase 0: certificate pre-check
. "$SCRIPT_DIR/tools/cert-state.sh"
state="$(sh "$SCRIPT_DIR/tools/cert-state.sh" "$proj" --days 21 || true)"
echo "Cert state: $state"

if [ "$state" != "ok" ]; then
  echo "No valid cert yet → install challenge-only config and issue certificates…"

  # Render a challenge-only config to a temp file
  chall_tmp="$(mktemp)"
  . "$SCRIPT_DIR/tools/write-challenge-conf.sh"
  sh "$SCRIPT_DIR/tools/write-challenge-conf.sh" "$MAIN_DOMAIN" $ALIASES > "$chall_tmp"

  # Stage -> nginx -t -> commit -> reload
  . "$SCRIPT_DIR/tools/stage-config.sh"
  tmp_conf="$(stage_config "$chall_tmp" "$MAIN_DOMAIN")"

  . "$SCRIPT_DIR/tools/nginx-test.sh"
  nginx_test "$tmp_conf"

  . "$SCRIPT_DIR/tools/commit-config.sh"
  commit_config "$tmp_conf" "$MAIN_DOMAIN"

  . "$SCRIPT_DIR/tools/reload-nginx.sh"
  "$SCRIPT_DIR/tools/reload-nginx.sh" || true

  # Issue/renew via your existing script (webroot)
  echo "Running cert issuance…"
  sh "$SCRIPT_DIR/tools/certbot-issuance.sh" "$proj"
fi

# ---- Phase 1: render and deploy the final TLS config
echo "Rendering server config..."
. "$SCRIPT_DIR/tools/render-server-conf.sh"
rendered_path="$(render_conf "$proj" "$MAIN_DOMAIN")"
[ -f "$rendered_path" ] || { echo "Render failed: $rendered_path not found"; exit 1; }

echo "Staging config..."
. "$SCRIPT_DIR/tools/stage-config.sh"
tmp_conf="$(stage_config "$rendered_path" "$MAIN_DOMAIN")"
[ -f "$tmp_conf" ] || { echo "Stage failed: $tmp_conf not found"; exit 1; }

echo "Testing nginx config..."
. "$SCRIPT_DIR/tools/nginx-test.sh"
nginx_test "$tmp_conf" || {
  echo "Heads up: if you see 'listen ... http2 is deprecated', switch to:"
  echo "  listen 443 ssl;   and add   http2 on;   at the server level."
  exit 1
}

echo "Committing config to live..."
. "$SCRIPT_DIR/tools/commit-config.sh"
commit_config "$tmp_conf" "$MAIN_DOMAIN"

# Ensure the project's docker compose stack is up
echo "Verifying application stack..."
. "$SCRIPT_DIR/tools/ensure-compose-up.sh"
ensure_compose_up "$proj"

# Final reload (best-effort)
. "$SCRIPT_DIR/tools/reload-nginx.sh"
"$SCRIPT_DIR/tools/reload-nginx.sh" || true

echo
echo "✅ DEPLOY SUCCESSFUL"
echo "   Config: $CONF_DIR/${MAIN_DOMAIN}.conf"
echo "   TLS: Certificates present and config live"
