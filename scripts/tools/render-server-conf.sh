#!/bin/sh
# Render server.conf using .env values
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via baton"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

render_conf() {
  proj="$1"
  domain="$2"

  src="$PROJECTS_DIR/$proj/server.conf"
  dst="$CONF_DIR/.${domain}.conf.rendered.$$"
  env_file="$PROJECTS_DIR/$proj/.env"

  load_dotenv "$env_file"

  # Use DOMAIN_NAME for everything; DOMAIN_ALIASES is space-separated
  envsubst '$DOMAIN_NAME $DOMAIN_ALIASES $DOCKER_NETWORK_SERVICE_ALIAS $APP_PORT' \
    < "$src" > "$dst"

  printf '%s\n' "$dst"
}
