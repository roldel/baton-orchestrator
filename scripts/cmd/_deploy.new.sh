#!/bin/sh
# scripts/cmd/_deploy.new.sh — canonical deploy (uses BASE_DIR)
set -e

if [ -z "${BASE_DIR:-}" ]; then
  echo "ERROR: BASE_DIR not set. Run via 'baton deploy <project>'." >&2
  exit 1
fi

. "$BASE_DIR/env-setup.sh"

proj="${1:-}"
[ -z "$proj" ] && { echo "Usage: baton deploy <project>"; exit 1; }

echo "Starting deploy for project: $proj"

echo "Validating project..."
. "$SCRIPT_DIR/tools/validate-project.sh"
validate_project "$proj" && echo "Project valid"

echo "Parsing domains..."
eval "$("$SCRIPT_DIR/tools/domain-name-aliases-retriever.sh" "$PROJECTS_DIR/$proj/server.conf")"
export MAIN_DOMAIN="$MAIN_DOMAIN_NAME"
export ALL_DOMAINS="$DOMAIN_ALIASES"

echo "Rendering config..."
. "$SCRIPT_DIR/tools/render-server-conf.sh"
rendered_path=$(render_conf "$proj" "$MAIN_DOMAIN" $ALL_DOMAINS)

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
