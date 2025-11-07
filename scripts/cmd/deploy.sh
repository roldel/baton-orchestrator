#!/bin/sh
# Deploy a project: render & commit nginx config, ensure stack is up, and
# verify/issue SSL certificates (with automatic ACME challenge swap if needed).
#
# Usage:
#   deploy.sh <project>
#
# Expects the following helpers to exist (same as before):
# - env-setup.sh -> sets BASE_DIR, SCRIPT_DIR, PROJECTS_DIR, ORCHESTRATOR_DIR, CONF_DIR, CERTS_DIR
# - tools/load-dotenv.sh -> load_dotenv <envfile>
# - tools/render-server-conf.sh -> render_conf <project> <domain>
# - tools/stage-config.sh -> stage_config <rendered_path> <domain>
# - tools/nginx-test.sh -> nginx_test <conf_path>
# - tools/commit-config.sh -> commit_config <conf_path> <domain>
# - tools/ensure-compose-up.sh -> ensure_compose_up <project>
# - tools/ensure-certs.sh (new) -> see above
set -eu

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: deploy.sh <project>"; exit 1; }

# Common environment/bootstrap
[ -n "${BASE_DIR:-}" ] || { echo "This script is intended to run via your baton entrypoint (BASE_DIR unset)."; exit 1; }
. "$BASE_DIR/env-setup.sh"

# Load project env
. "$SCRIPT_DIR/tools/load-dotenv.sh"
env_file="$PROJECTS_DIR/$proj/.env"
[ -f "$env_file" ] || { echo "Missing env for project: $env_file"; exit 1; }
load_dotenv "$env_file" >/dev/null

MAIN_DOMAIN="${DOMAIN_NAME:-}"
[ -n "$MAIN_DOMAIN" ] || { echo "DOMAIN_NAME missing in $env_file"; exit 1; }

echo "==> Deploying project: $proj"
echo "    Domain: $MAIN_DOMAIN"
[ -n "${DOMAIN_ALIASES:-}" ] && echo "    Aliases: $DOMAIN_ALIASES"

# 1) Render server config
echo "Rendering server config..."
. "$SCRIPT_DIR/tools/render-server-conf.sh"
rendered_path="$(render_conf "$proj" "$MAIN_DOMAIN")"
[ -f "$rendered_path" ] || { echo "Render failed: $rendered_path not found"; exit 1; }

# 2) Stage config (place into container-visible temp path)
echo "Staging config..."
. "$SCRIPT_DIR/tools/stage-config.sh"
tmp_conf="$(stage_config "$rendered_path" "$MAIN_DOMAIN")"
[ -f "$tmp_conf" ] || { echo "Stage failed: $tmp_conf not found"; exit 1; }

# 3) nginx -t inside ingress container
echo "Testing nginx config..."
. "$SCRIPT_DIR/tools/nginx-test.sh"
nginx_test "$tmp_conf"

# 4) Commit config to live
echo "Committing config to live..."
. "$SCRIPT_DIR/tools/commit-config.sh"
commit_config "$tmp_conf" "$MAIN_DOMAIN"

# 5) Ensure the project's docker compose stack is up (no templates)
echo "Verifying application stack..."
. "$SCRIPT_DIR/tools/ensure-compose-up.sh"
ensure_compose_up "$proj"

# 6) Ensure SSL certificates (may temporarily swap to challenge-only config if needed)
echo "Checking SSL certificates..."
. "$SCRIPT_DIR/tools/ensure-certs.sh"
sh "$SCRIPT_DIR/tools/ensure-certs.sh" "$proj"

echo
echo "✅ DEPLOY SUCCESSFUL"
echo "   Config: $CONF_DIR/${MAIN_DOMAIN}.conf"
echo "   TLS: Verified or issued as needed"
