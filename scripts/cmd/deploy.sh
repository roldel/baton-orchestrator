#!/bin/sh
# cmd/deploy.sh
# Usage: baton deploy <project>
# Safe: No config is live until nginx -t passes

set -e

# ------------------------------------------------------------------
# 1. Load environment
# ------------------------------------------------------------------
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/../env-setup.sh"

# ------------------------------------------------------------------
# 2. Parse arguments
# ------------------------------------------------------------------
proj="$1"
[ -z "$proj" ] && {
    echo "Usage: baton deploy <project>" >&2
    echo "Example: baton deploy demo-website" >&2
    exit 1
}

# ------------------------------------------------------------------
# 3. Validate project
# ------------------------------------------------------------------
. "$SCRIPT_DIR/../tools/validate-project.sh"
validate_project "$proj"

# ------------------------------------------------------------------
# 4. Parse domains from server.conf
# ------------------------------------------------------------------
. "$SCRIPT_DIR/../tools/parse-domains.sh"
parse_domains "$PROJECTS_DIR/$proj/server.conf"

export MAIN_DOMAIN="$PARSED_MAIN_DOMAIN"
export ALL_DOMAINS="$PARSED_ALL_DOMAINS"

echo "Project:     $proj"
echo "Main domain: $MAIN_DOMAIN"
echo "All domains: $ALL_DOMAINS"
echo ""

# ------------------------------------------------------------------
# 5. Stage config to temp file
# ------------------------------------------------------------------
. "$SCRIPT_DIR/../tools/stage-config.sh"
tmp_conf=$(stage_config "$PROJECTS_DIR/$proj/server.conf" "$MAIN_DOMAIN")

# ------------------------------------------------------------------
# 6. Test config with nginx
# ------------------------------------------------------------------
. "$SCRIPT_DIR/../tools/nginx-test.sh"
if ! nginx_test "$tmp_conf"; then
    echo "Config test failed — removing staged file" >&2
    rm -f "$tmp_conf"
    exit 1
fi

# ------------------------------------------------------------------
# 7. Commit: atomic move to live
# ------------------------------------------------------------------
. "$SCRIPT_DIR/../tools/commit-config.sh"
commit_config "$tmp_conf" "$MAIN_DOMAIN"

echo "Deployed config → $CONF_DIR/${MAIN_DOMAIN}.conf"
echo ""
echo "Next: baton will check SSL certificate..."