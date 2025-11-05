#!/bin/sh
# tools/render-server-conf.sh
. "$(dirname "$0")/../env-setup.sh"

render_conf() {
    proj=$1
    domain=$2
    shift 2
    aliases="$*"

    src="$PROJECTS_DIR/$proj/server.conf"
    dst="$CONF_DIR/${domain}.conf"

    # Build alias string for nginx
    alias_str=""
    for a in $aliases; do alias_str="$alias_str $a"; done

    # Simple env-subst (POSIX)
    MAIN_DOMAIN_NAME="$domain" \
    DOMAIN_ALIASES="$alias_str" \
    DOCKER_COMPOSE_SERVICE_NETWORK_ALIAS="${proj}-service-exposing-application-server" \
    APP_PORT="8000" \   # you can make this configurable per-project later
    envsubst '$MAIN_DOMAIN_NAME $DOMAIN_ALIASES $DOCKER_COMPOSE_SERVICE_NETWORK_ALIAS $APP_PORT' \
        < "$src" > "$dst"

    echo "Rendered $dst"
}