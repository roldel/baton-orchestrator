#!/bin/sh
# Deploy with cert-first gating:
# 1) Render final server conf (not committed yet)
# 2) Check certificate state
#    - If OK: stage final -> nginx -t -> commit -> reload
#    - If NOT OK: stage challenge -> nginx -t -> commit -> reload
#                 run certbot -> verify -> stage final -> nginx -t -> commit -> reload
# 3) Ensure app stack is up
set -eu

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: deploy.sh <project>"; exit 1; }

[ -n "${BASE_DIR:-}" ] || { echo "BASE_DIR not set"; exit 1; }
. "$BASE_DIR/env-setup.sh"

# Helpers we rely on:
# - tools/load-dotenv.sh            -> load_dotenv <envfile>
# - tools/render-server-conf.sh     -> render_conf <project> <domain>
# - tools/stage-config.sh           -> stage_config <rendered_path> <domain>
# - tools/nginx-test.sh             -> nginx_test <host_tmp_conf>
# - tools/commit-config.sh          -> commit_config <host_tmp_conf> <domain>
# - tools/reload-nginx.sh           -> reload nginx inside ingress (best-effort)
# - tools/ensure-ingress-ready.sh   -> waits for ingress (soft-fail allowed)
# - tools/force-commit-challenge.sh -> offline swap challenge conf + restart ingress
# - tools/write-challenge-conf.sh   -> prints a HTTP-only challenge server block
# - tools/cert-state.sh             -> prints "ok|missing|expiring_soon|sans_missing:<name>"
# - tools/certbot-issuance.sh       -> performs LE issuance/renewal via webroot
# - tools/ensure-compose-up.sh      -> ensure_compose_up <project>

. "$SCRIPT_DIR/tools/load-dotenv.sh"
env_file="$PROJECTS_DIR/$proj/.env"
[ -f "$env_file" ] || { echo "Missing env: $env_file"; exit 1; }
load_dotenv "$env_file" >/dev/null

MAIN_DOMAIN="${DOMAIN_NAME:-}"
ALIASES="${DOMAIN_ALIASES:-}"
[ -n "$MAIN_DOMAIN" ] || { echo "DOMAIN_NAME missing in $env_file"; exit 1; }

echo "==> Deploying project: $proj"
echo "    Domain: $MAIN_DOMAIN"
[ -n "$ALIASES" ] && echo "    Aliases: $ALIASES"

# If ingress is currently crash-looping due to an old bad TLS file, we may need offline fallback later.
. "$SCRIPT_DIR/tools/ensure-ingress-ready.sh" || true

# ---- Step 1: render final server conf (NOT committed yet)
echo "Rendering final server config..."
. "$SCRIPT_DIR/tools/render-server-conf.sh"
final_rendered="$(render_conf "$proj" "$MAIN_DOMAIN")"
[ -f "$final_rendered" ] || { echo "Render failed: $final_rendered not found"; exit 1; }

# ---- Step 2: check certificate state (before testing final TLS config)
. "$SCRIPT_DIR/tools/cert-state.sh"
cert_state="$(sh "$SCRIPT_DIR/tools/cert-state.sh" "$proj" --days 21 || true)"
echo "Certificate state: $cert_state"

if [ "$cert_state" = "ok" ]; then
  # ---- Fast path: certs are fine → deploy final TLS config now
  echo "Certs valid → staging final TLS config..."
  . "$SCRIPT_DIR/tools/stage-config.sh"
  tmp_final="$(stage_config "$final_rendered" "$MAIN_DOMAIN")"

  echo "nginx -t on final config (with TLS)..."
  . "$SCRIPT_DIR/tools/nginx-test.sh"
  if ! nginx_test "$tmp_final"; then
    echo "Hint: replace 'listen 443 ssl http2;' with:"
    echo "  listen 443 ssl;"
    echo "  http2 on;"
    exit 1
  fi

  echo "Committing final config..."
  . "$SCRIPT_DIR/tools/commit-config.sh"
  commit_config "$tmp_final" "$MAIN_DOMAIN"

  . "$SCRIPT_DIR/tools/reload-nginx.sh"
  "$SCRIPT_DIR/tools/reload-nginx.sh" || true

else
  # ---- Certs missing/expiring/SAN mismatch → load challenge config first
  echo "Certs not valid → installing challenge-only config, then issuing certificates..."

  # Build challenge-only HTTP config
  chall_tmp="$(mktemp)"
  . "$SCRIPT_DIR/tools/write-challenge-conf.sh"
  sh "$SCRIPT_DIR/tools/write-challenge-conf.sh" "$MAIN_DOMAIN" $ALIASES > "$chall_tmp"

  # Try normal stage/test/commit; if ingress isn't ready, do offline swap and restart
  if sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh" --max-wait 15; then
    echo "Staging challenge config..."
    . "$SCRIPT_DIR/tools/stage-config.sh"
    tmp_chal="$(stage_config "$chall_tmp" "$MAIN_DOMAIN")"

    echo "nginx -t on challenge config..."
    . "$SCRIPT_DIR/tools/nginx-test.sh"
    nginx_test "$tmp_chal"

    echo "Committing challenge config..."
    . "$SCRIPT_DIR/tools/commit-config.sh"
    commit_config "$tmp_chal" "$MAIN_DOMAIN"

    . "$SCRIPT_DIR/tools/reload-nginx.sh"
    "$SCRIPT_DIR/tools/reload-nginx.sh" || true
  else
    echo "Ingress not ready → offline commit of challenge config"
    . "$SCRIPT_DIR/tools/force-commit-challenge.sh"
    sh "$SCRIPT_DIR/tools/force-commit-challenge.sh" "$MAIN_DOMAIN" "$chall_tmp"
    # Wait for ingress to come up on safe HTTP config
    sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh" --max-wait 60
  fi

  # Issue/renew with certbot (webroot)
  echo "Issuing/renewing certificates with certbot..."
  sh "$SCRIPT_DIR/tools/certbot-issuance.sh" "$proj"

  # Verify certs now OK
  new_state="$(sh "$SCRIPT_DIR/tools/cert-state.sh" "$proj" --days 21 || true)"
  [ "$new_state" = "ok" ] || { echo "ERROR: certificates still not valid after issuance ($new_state)"; exit 1; }

  # Now deploy the final TLS config
  echo "Staging final TLS config..."
  tmp_final="$(stage_config "$final_rendered" "$MAIN_DOMAIN")"

  echo "nginx -t on final config (with TLS)..."
  if ! nginx_test "$tmp_final"; then
    echo "Hint: replace 'listen 443 ssl http2;' with:"
    echo "  listen 443 ssl;"
    echo "  http2 on;"
    exit 1
  fi

  echo "Committing final config..."
  . "$SCRIPT_DIR/tools/commit-config.sh"
  commit_config "$tmp_final" "$MAIN_DOMAIN"

  . "$SCRIPT_DIR/tools/reload-nginx.sh"
  "$SCRIPT_DIR/tools/reload-nginx.sh" || true
fi

# ---- Step 3: ensure the app stack is up
echo "Verifying application stack..."
. "$SCRIPT_DIR/tools/ensure-compose-up.sh"
ensure_compose_up "$proj"

echo
echo "✅ DEPLOY COMPLETE"
echo "   Active config: $CONF_DIR/${MAIN_DOMAIN}.conf"
echo "   TLS: Ready"
