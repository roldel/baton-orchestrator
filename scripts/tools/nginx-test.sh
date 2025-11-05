#!/bin/sh
# tools/nginx-test.sh

. "$(dirname "$0")/../env-setup.sh"

nginx_test() {
    conf="$1"
    echo "Testing config: $conf"

    if ! docker exec ingress-nginx nginx -t -c "$conf" >/dev/null 2>&1; then
        echo "nginx -t failed:" >&2
        docker exec ingress-nginx nginx -t -c "$conf" >&2
        return 1
    fi

    echo "Config valid"
    return 0
}