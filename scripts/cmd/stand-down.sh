#!/bin/sh
# Stand down a project:
# - Validate project exists
# - Stop its containers
# - Remove its nginx server config
# - Test nginx config
# - Reload nginx

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
TOOLS_DIR="$BASE_DIR/scripts/tools"

COMPOSE_CMD="$TOOLS_DIR/helpers/compose-cmd.sh"
RESOLVE_HELPER="$TOOLS_DIR/helpers/resolve-compose-files.sh"
NGINX_TEST="$TOOLS_DIR/nginx/test-config.sh"
NGINX_RELOAD="$TOOLS_DIR/nginx/reload.sh"

ENV_FILE="$PROJECT_DIR/.env"
NGINX_CONF_DIR="$BASE_DIR/orchestrator/nginx/conf.d"
BACKUP_DIR="$BASE_DIR/tmp/nginx-backups"

echo "[stand-down] Standing down project: $PROJECT"
echo "[stand-down] Project dir: $PROJECT_DIR"

# 1) Validate project directory exists
sh "$TOOLS_DIR/projects/validate-exists.sh" "$PROJECT"

if [ ! -f "$ENV_FILE" ]; then
  echo "[stand-down] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

# Read in isolated subshells, not sourced into this shell directly: BASE_DIR
# and TOOLS_DIR are both reused below (to locate webhook-deactivate.sh and
# the nginx helpers), and a project's own .env sourced directly could
# redefine either, redirecting those calls to an attacker-controlled script
# run with this script's (root) privileges.
DOMAIN_NAME="$(
  set +eu
  . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${DOMAIN_NAME:-}"
  fi
)"
STATIC_SITE="$(
  set +eu
  . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${STATIC_SITE:-no}"
  fi
)"
[ -n "$STATIC_SITE" ] || STATIC_SITE="no"

# 2) Remove webhook (guarded on DOMAIN_NAME to avoid a spurious "missing
# DOMAIN_NAME" failure from webhook-deactivate.sh if the .env is incomplete).
# Tolerated like the `docker compose down` below: a transient failure here
# (e.g. nginx reload) must not abort stand-down before containers are
# stopped and the site's own nginx conf is removed — steps 5-6 re-test and
# reload nginx anyway, which catches any lingering config problem.
if [ -n "${DOMAIN_NAME:-}" ]; then
  sh "$BASE_DIR/scripts/cmd/webhook-deactivate.sh" "$PROJECT" || {
    echo "[stand-down] WARNING: webhook deactivation failed; continuing with stand-down." >&2
  }
else
  echo "[stand-down] No DOMAIN_NAME set — skipping webhook deactivation"
fi

# 3) Stop project containers (static sites have no compose file / container)
if [ "$STATIC_SITE" = "yes" ]; then
  echo "[stand-down] Static site — no containers to stop"
else
  if [ ! -f "$COMPOSE_CMD" ]; then
    echo "[stand-down] ERROR: compose-cmd helper not found: $COMPOSE_CMD" >&2
    exit 1
  fi

  if [ -f "$RESOLVE_HELPER" ]; then
    COMPOSE_FILES="$(sh "$RESOLVE_HELPER" "$PROJECT_DIR")"
    echo "[stand-down] Using compose file(s):"
    printf '%s\n' "$COMPOSE_FILES" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      echo "[stand-down]   - $f"
    done
  fi

  echo "[stand-down] docker compose down"
  sh "$COMPOSE_CMD" "$PROJECT_DIR" down || {
    echo "[stand-down] WARNING: docker compose down failed (containers may already be stopped)." >&2
  }
fi

# 4) Remove the nginx server config for this project (keyed by DOMAIN_NAME)
mkdir -p "$BACKUP_DIR"

remove_site_conf() {
  SITE_KEY="$1"
  [ -n "$SITE_KEY" ] || return 0
  CONF_FILE="$NGINX_CONF_DIR/${SITE_KEY}.conf"
  if [ -f "$CONF_FILE" ]; then
    TS="$(date '+%Y%m%d-%H%M%S')"
    BACKUP_FILE="$BACKUP_DIR/${SITE_KEY}.conf.removed.$TS"
    echo "[stand-down] Moving nginx config: $CONF_FILE → $BACKUP_FILE"
    mv "$CONF_FILE" "$BACKUP_FILE"
  else
    echo "[stand-down] No nginx server config found: $CONF_FILE (nothing to remove)"
  fi
}

remove_site_conf "${DOMAIN_NAME:-}"

# 5) Test nginx config
sh "$NGINX_TEST"

# 6) Reload nginx
sh "$NGINX_RELOAD"

echo "[stand-down] Project '$PROJECT' has been stood down:"
echo "             - Containers stopped"
echo "             - Nginx server config removed"
echo "             - Nginx reloaded"
