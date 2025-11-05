#!/bin/sh
# Render from .env and deploy (DOMAIN_NAME is canonical)
set -e
[ -n "${BASE_DIR:-}" ] || { echo "ERROR: BASE_DIR not set. Run via 'baton deploy <project>'." >&2; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

proj="${1:-}"; [ -n "$proj" ] || { echo "Usage: baton deploy <project>"; exit 1; }

echo "Starting deploy for project: $proj"

. "$SCRIPT_DIR/tools/validate-project.sh"
validate_project "$proj" && echo "Project valid"

# .env has been validated and loaded inside validate_project
env_file="$PROJECTS_DIR/$proj/.env"; load_dotenv "$env_file" >/dev/null

MAIN_DOMAIN="$DOMAIN_NAME"

echo "Rendering config with .env (DOMAIN_NAME=$DOMAIN_NAME ALIASES='$DOMAIN_ALIASES' APP_PORT=$APP_PORT)..."
. "$SCRIPT_DIR/tools/render-server-conf.sh"
rendered_path=$(render_conf "$proj" "$MAIN_DOMAIN")

echo "Staging config..."
. "$SCRIPT_DIR/tools/stage-config.sh"
tmp_conf=$(stage_config "$rendered_path" "$MAIN_DOMAIN")

echo "Testing with nginx..."
. "$SCRIPT_DIR/tools/nginx-test.sh"
nginx_test "$tmp_conf" && echo "Config test PASSED"

echo "Committing to live..."
. "$SCRIPT_DIR/tools/commit-config.sh"
commit_config "$tmp_conf" "$MAIN_DOMAIN"

echo
echo "DEPLOY SUCCESSFUL"
echo "Config: $CONF_DIR/${MAIN_DOMAIN}.conf"
echo "Next: Run 'baton ssl-issue $proj' when ready"
