#!/bin/sh
# use .env + envsubst to render, then stage/test/commit
set -e
[ -n "${BASE_DIR:-}" ] || { echo "ERROR: BASE_DIR not set. Run via 'baton deploy <project>'." >&2; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

proj="${1:-}"
[ -z "$proj" ] && { echo "Usage: baton deploy <project>"; exit 1; }

echo "Starting deploy for project: $proj"

echo "Validating project..."
. "$SCRIPT_DIR/tools/validate-project.sh"
validate_project "$proj" && echo "Project valid"

# After validate_project, .env is loaded and MAIN_DOMAIN_NAME/DOMAIN_ALIASES set
MAIN_DOMAIN="$MAIN_DOMAIN_NAME"
ALL_DOMAINS="$DOMAIN_ALIASES"

echo "Env: MAIN_DOMAIN=$MAIN_DOMAIN  ALIASES='${ALL_DOMAINS}'  APP_PORT=$APP_PORT  ALIAS=$DOCKER_NETWORK_SERVICE_ALIAS"

echo "Rendering config with .env..."
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
