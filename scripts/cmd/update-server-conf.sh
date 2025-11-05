#!/bin/sh
# re-render from .env and apply
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via 'baton update-server-conf <project>'"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

proj="${1:-}"
[ -n "$proj" ] || { echo "Usage: baton update-server-conf <project>"; exit 1; }

. "$SCRIPT_DIR/tools/validate-project.sh"
validate_project "$proj"

MAIN_DOMAIN="$MAIN_DOMAIN_NAME"

. "$SCRIPT_DIR/tools/render-server-conf.sh"
rendered=$(render_conf "$proj" "$MAIN_DOMAIN")

. "$SCRIPT_DIR/tools/stage-config.sh"
tmp=$(stage_config "$rendered" "$MAIN_DOMAIN")

. "$SCRIPT_DIR/tools/nginx-test.sh"
nginx_test "$tmp"

. "$SCRIPT_DIR/tools/commit-config.sh"
commit_config "$tmp" "$MAIN_DOMAIN"

docker exec ingress-nginx nginx -s reload || true
echo "Updated and reloaded Nginx for $MAIN_DOMAIN"
