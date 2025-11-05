#!/bin/sh
. "$(dirname "$0")/../env-setup.sh"

render_conf() {
  proj="$1"
  domain="$2"
  shift 2
  aliases="$*"

  src="$PROJECTS_DIR/$proj/server.conf"
  dst="$CONF_DIR/.${domain}.conf.rendered.$$"

  alias_str=""
  for a in $aliases; do alias_str="$alias_str $a"; done

  : "${APP_PORT:=8000}"
  : "${DOCKER_COMPOSE_SERVICE_NETWORK_ALIAS:=${proj}-service-exposing-application-server}"

  MAIN_DOMAIN_NAME="$domain" \
  DOMAIN_ALIASES="$alias_str" \
  DOCKER_COMPOSE_SERVICE_NETWORK_ALIAS="$DOCKER_COMPOSE_SERVICE_NETWORK_ALIAS" \
  APP_PORT="$APP_PORT" \
  envsubst '$MAIN_DOMAIN_NAME $DOMAIN_ALIASES $DOCKER_COMPOSE_SERVICE_NETWORK_ALIAS $APP_PORT' \
    < "$src" > "$dst"

  echo "$dst"
}
