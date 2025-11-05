#!/bin/sh
set -e
. "$(dirname "$0")/../env-setup.sh"

proj=$1
[ -z "$proj" ] && { echo "Usage: baton ssl-renew-now <project>"; exit 1; }

# Find domain from the *active* conf file
conf_file=$(find "$CONF_DIR" -name "*.conf" -exec grep -l "server_name.* $proj" {} + | head -n1)
if [ -z "$conf_file" ]; then
    echo "No active conf for project $proj" >&2
    exit 1
fi
domain=$(grep "server_name" "$conf_file" | sed -E 's/.*server_name +([^ ;]+).*/\1/' | head -n1)

. "$SCRIPT_DIR/../tools/certbot-renew.sh"
renew_cert "$domain"

. "$SCRIPT_DIR/../tools/reload-nginx.sh"
reload_nginx

echo "SSL renewed for $domain"