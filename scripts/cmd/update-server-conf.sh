#!/bin/sh
# scripts/cmd/update-server-conf.sh — use server.conf as-is (no render)
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via 'baton update-server-conf <project>'"; exit 1; }
. "$BASE_DIR/env-setup.sh"

proj="${1:-}"
[ -n "$proj" ] || { echo "Usage: baton update-server-conf <project>"; exit 1; }

. "$SCRIPT_DIR/tools/validate-project.sh"
validate_project "$proj"

eval "$("$SCRIPT_DIR/tools/domain-name-aliases-retriever.sh" "$PROJECTS_DIR/$proj/server.conf")"

src_conf="$PROJECTS_DIR/$proj/server.conf"

. "$SCRIPT_DIR/tools/stage-config.sh"
tmp=$(stage_config "$src_conf" "$MAIN_DOMAIN_NAME")

. "$SCRIPT_DIR/tools/nginx-test.sh"
nginx_test "$tmp"

. "$SCRIPT_DIR/tools/commit-config.sh"
commit_config "$tmp" "$MAIN_DOMAIN_NAME"

docker exec ingress-nginx nginx -s reload || true
echo "Updated and reloaded Nginx for $MAIN_DOMAIN_NAME"
