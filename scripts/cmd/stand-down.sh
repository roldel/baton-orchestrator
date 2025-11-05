#!/bin/sh
set -e
. "$(dirname "$0")/../env-setup.sh"

proj=$1
[ -z "$proj" ] && { echo "Usage: baton stand-down <project>"; exit 1; }

# Remove conf + cert (optional) + reload
conf_file=$(find "$CONF_DIR" -name "*.conf" -exec grep -l " $proj" {} + | head -n1)
if [ -n "$conf_file" ]; then
    rm -f "$conf_file"
    echo "Removed $conf_file"
fi

. "$SCRIPT_DIR/../tools/nginx-test.sh"
nginx_test || true   # ignore error if no sites left

. "$SCRIPT_DIR/../tools/reload-nginx.sh"
reload_nginx

echo "$proj stood down"