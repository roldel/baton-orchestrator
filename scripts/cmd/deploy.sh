#!/bin/sh
# scripts/cmd/deploy.sh
# Full debug version with clear output

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/../env-setup.sh"

echo "Starting deploy for project: $1"

proj="$1"
[ -z "$proj" ] && { echo "Usage: baton deploy <project>"; exit 1; }

echo "Validating project..."
. "$SCRIPT_DIR/../tools/validate-project.sh"
validate_project "$proj" && echo "Project valid"

echo "Parsing domains..."
. "$SCRIPT_DIR/../tools/parse-domains.sh"
parse_domains "$PROJECTS_DIR/$proj/server.conf"

export MAIN_DOMAIN="$PARSED_MAIN_DOMAIN"
export ALL_DOMAINS="$PARSED_ALL_DOMAINS"

echo "Main domain: $MAIN_DOMAIN"
echo "All domains: $ALL_DOMAINS"

echo "Staging config..."
. "$SCRIPT_DIR/../tools/stage-config.sh"
tmp_conf=$(stage_config "$PROJECTS_DIR/$proj/server.conf" "$MAIN_DOMAIN")

echo "Testing with nginx..."
. "$SCRIPT_DIR/../tools/nginx-test.sh"
nginx_test "$tmp_conf" && echo "Config test PASSED"

echo "Committing to live..."
. "$SCRIPT_DIR/../tools/commit-config.sh"
commit_config "$tmp_conf" "$MAIN_DOMAIN"

echo ""
echo "DEPLOY SUCCESSFUL"
echo "Config: $CONF_DIR/${MAIN_DOMAIN}.conf"
echo "Next: Run 'baton ssl-issue $proj' when ready"