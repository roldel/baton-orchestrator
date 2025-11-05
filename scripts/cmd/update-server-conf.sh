#!/bin/sh
set -e
. "$(dirname "$0")/../env-setup.sh"

proj=$1
domain=$2
shift 2 || true
aliases="$*"

[ -z "$proj" ]   && { echo "Usage: baton update-server-conf <project> <main-domain> [alias...]"; exit 1; }
[ -z "$domain" ] && { echo "Main domain required"; exit 1; }

. "$SCRIPT_DIR/../tools/validate-project.sh"
validate_project "$proj"

. "$SCRIPT_DIR/../tools/render-server-conf.sh"
render_conf "$proj" "$domain" $aliases

. "$SCRIPT_DIR/../tools/nginx-test.sh"
nginx_test

. "$SCRIPT_DIR/../tools/reload-nginx.sh"
reload_nginx

echo "Server conf updated for $proj → $domain"