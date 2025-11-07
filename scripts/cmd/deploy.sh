#!/bin/sh
# scripts/cmd/deploy.sh
# Deploy a project with safe certificate gating.
# Handles: no certs, valid certs, expiring certs, SAN mismatches.
set -eu

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: baton deploy <project>"; exit 1; }

# Load environment (BASE_DIR, paths, helpers)
[ -n "${BASE_DIR:-}" ] || { echo "BASE_DIR not set – run via 'baton'"; exit 1; }
. "$BASE_DIR/env-setup.sh"

# ----------------------------------------------------------------------
# Helper sourcing
# ----------------------------------------------------------------------
. "$SCRIPT_DIR/tools/load-dotenv.sh"
. "$SCRIPT_DIR/tools/render-server-conf.sh"
. "$SCRIPT_DIR/tools/stage-config.sh"
. "$SCRIPT_DIR/tools/nginx-test.sh"
. "$SCRIPT_DIR/tools/commit-config.sh"
. "$SCRIPT_DIR/tools/reload-nginx.sh"
. "$SCRIPT_DIR/tools/write-challenge-conf.sh"
. "$SCRIPT_DIR/tools/cert-state.sh"
. "$SCRIPT_DIR/tools/certbot-issuance.sh"
. "$SCRIPT_DIR/tools/ensure-ingress-ready.sh"
. "$SCRIPT_DIR/tools/ensure-compose-up.sh"

# ----------------------------------------------------------------------
# Load project .env
# ----------------------------------------------------------------------
env_file="$PROJECTS_DIR/$proj/.env"
[ -f "$env_file" ] || { echo "Missing .env: $env_file"; exit 1; }
load_dotenv "$env_file" >/dev/null

MAIN_DOMAIN="${DOMAIN_NAME:?DOMAIN_NAME missing}"
ALIASES="${DOMAIN_ALIASES:-}"

echo "==> Deploying project: $proj"
echo "    Domain : $MAIN_DOMAIN"
[ -n "$ALIASES" ] && echo "    Aliases: $ALIASES"

# ----------------------------------------------------------------------
# 1. Render final server config (once – reused later)
# ----------------------------------------------------------------------
echo "Rendering final server config..."
final_rendered="$(render_conf "$proj" "$MAIN_DOMAIN")"
[ -f "$final_rendered" ] || { echo "Render failed – no file"; exit 1; }

# ----------------------------------------------------------------------
# 2. Determine certificate state
# ----------------------------------------------------------------------
cert_state="$(sh "$SCRIPT_DIR/tools/cert-state.sh" "$proj" --days 21 || echo "unknown")"
echo "Certificate state: $cert_state"

# ----------------------------------------------------------------------
# Helper: safely stage + test + commit a config
# ----------------------------------------------------------------------
deploy_config() {
  local src="$1" desc="$2"
  echo "$desc"
  tmp="$(stage_config "$src" "$MAIN_DOMAIN")"
  echo "Testing config with nginx -t..."
  if nginx_test "$tmp"; then
    echo "Config valid → committing"
    commit_config "$tmp" "$MAIN_DOMAIN"
    reload_nginx || true
    return 0
  else
    echo "ERROR: $desc failed nginx -t – aborting"
    rm -f "$tmp"
    return 1
  fi
}

# ----------------------------------------------------------------------
# FAST PATH – certs already OK
# ----------------------------------------------------------------------
if [ "$cert_state" = "ok" ]; then
  echo "Certs valid → deploying final TLS config"
  if deploy_config "$final_rendered" "Deploying final TLS config..."; then
    echo "Fast-path deployment complete"
  else
    exit 1
  fi

# ----------------------------------------------------------------------
# SLOW PATH – need to issue/renew certs
# ----------------------------------------------------------------------
else
  echo "Certs not valid ($cert_state) → using challenge-only config first"

  # ---- a) Build challenge-only config
  chall_tmp="$(mktemp)"
  trap 'rm -f "$chall_tmp"' EXIT
  sh "$SCRIPT_DIR/tools/write-challenge-conf.sh" "$MAIN_DOMAIN" $ALIASES > "$chall_tmp"

  # ---- b) Try normal staging; fall back to offline swap if ingress is down
  if sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh" --max-wait 15; then
    if ! deploy_config "$chall_tmp" "Staging challenge-only config..."; then
      echo "Challenge config invalid – cannot continue"
      exit 1
    fi
  else
    echo "Ingress not healthy → forcing challenge config offline"
    # Simple offline swap – copy directly and restart container
    cp "$chall_tmp" "$CONF_DIR/${MAIN_DOMAIN}.conf"
    docker compose -f "$ORCHESTRATOR_DIR/docker-compose.yml" restart ingress-nginx >/dev/null
    sh "$SCRIPT_DIR/tools/ensure-ingress-ready.sh" --max-wait 60 || {
      echo "Ingress failed to come up with challenge config"
      exit 1
    }
  fi

  # ---- c) Issue / renew certificates
  echo "Running certbot issuance..."
  if ! sh "$SCRIPT_DIR/tools/certbot-issuance.sh" "$proj"; then
    echo "Certbot failed – leaving challenge config in place"
    exit 1
  fi

  # ---- d) Verify certs are now OK
  new_state="$(sh "$SCRIPT_DIR/tools/cert-state.sh" "$proj" --days 21 || echo "unknown")"
  if [ "$new_state" != "ok" ]; then
    echo "ERROR: Certificates still not valid after issuance ($new_state)"
    exit 1
  fi

  #