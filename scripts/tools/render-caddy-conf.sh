#!/bin/sh
# scripts/tools/render-caddy-conf.sh
set -eu

render_caddy_conf() {
  proj="$1"
  template="$PROJECTS_DIR/$proj/server.conf"
  [ -f "$template" ] || { echo "ERROR: server.conf missing: $template" >&2; exit 1; }

  # Normalize aliases: comma → space, trim
  if [ -n "${DOMAIN_ALIASES:-}" ]; then
    ALIASES="$(printf '%s' "$DOMAIN_ALIASES" | tr ',' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//')"
  else
    ALIASES=""
  fi

  # Export all vars for envsubst
  export DOMAIN_NAME ALIASES APP_PORT DOCKER_NETWORK_SERVICE_ALIAS
  export DOMAIN_ADMIN_EMAIL="${DOMAIN_ADMIN_EMAIL:-}"

  # Render using envsubst (only defined vars)
  envsubst '$DOMAIN_NAME,$DOMAIN_ALIASES,$APP_PORT,$DOCKER_NETWORK_SERVICE_ALIAS,$DOMAIN_ADMIN_EMAIL' < "$template"
}