#!/bin/sh
# Stand down a project:
# - Cancel queued webhook tasks, or stop if one is already running
# - Stop its containers
# - Remove its nginx server config
# - Test nginx config and reload, restoring the vhost if that fails

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

BASE_DIR="${BATON_BASE_DIR:-/opt/baton-orchestrator}"
PROJECTS_ROOT="${BATON_PROJECTS_ROOT:-/srv/projects}"
PROJECT_DIR="$PROJECTS_ROOT/$PROJECT"
TOOLS_DIR="$BASE_DIR/scripts/tools"

COMPOSE_CMD="${BATON_COMPOSE_CMD:-$TOOLS_DIR/helpers/compose-cmd.sh}"
RESOLVE_HELPER="$TOOLS_DIR/helpers/resolve-compose-files.sh"
NGINX_TEST="${BATON_NGINX_TEST:-$TOOLS_DIR/nginx/test-config.sh}"
NGINX_RELOAD="${BATON_NGINX_RELOAD:-$TOOLS_DIR/nginx/reload.sh}"
SITE_KEY_HELPER="${BATON_SITE_KEY_HELPER:-$BASE_DIR/scripts/tools/helpers/compute-site-key.sh}"
QUIESCE="$TOOLS_DIR/webhook/quiesce-project.sh"

ENV_FILE="$PROJECT_DIR/.env"
NGINX_CONF_DIR="$BASE_DIR/orchestrator/nginx/conf.d"
BACKUP_DIR="$BASE_DIR/tmp/nginx-backups"

echo "[stand-down] Standing down project: $PROJECT"
echo "[stand-down] Project dir: $PROJECT_DIR"

sh "$TOOLS_DIR/projects/validate-exists.sh" "$PROJECT"

if [ ! -f "$ENV_FILE" ]; then
  echo "[stand-down] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

# A queued task can compose up after the containers are stopped. Refuse
# while one is in processing/, and cancel the ones still queued.
if ! sh "$QUIESCE" "$PROJECT"; then
  echo "[stand-down] ERROR: could not quiesce webhook tasks for $PROJECT" >&2
  exit 1
fi

if ! DOMAIN_NAME="$(sh "$SITE_KEY_HELPER" "$PROJECT")"; then
  echo "[stand-down] ERROR: could not resolve SITE_KEY for $PROJECT" >&2
  exit 1
fi

STATIC_SITE="$(
  set +eu
  . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${STATIC_SITE:-no}"
  fi
)"
[ -n "$STATIC_SITE" ] || STATIC_SITE="no"

if ! sh "$BASE_DIR/scripts/cmd/webhook-deactivate.sh" "$PROJECT"; then
  echo "[stand-down] WARNING: webhook deactivation failed; continuing with stand-down." >&2
fi

CONTAINERS_STOPPED=0
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
  if sh "$COMPOSE_CMD" "$PROJECT_DIR" down; then
    CONTAINERS_STOPPED=1
  else
    _sd_ps=$(mktemp)
    if ! sh "$COMPOSE_CMD" "$PROJECT_DIR" ps --format '{{.Name}}' > "$_sd_ps"; then
      rm -f "$_sd_ps"
      echo "[stand-down] ERROR: docker compose down failed and compose ps failed" >&2
      exit 1
    fi
    if [ -s "$_sd_ps" ]; then
      rm -f "$_sd_ps"
      echo "[stand-down] ERROR: docker compose down failed and containers are still running" >&2
      exit 1
    fi
    rm -f "$_sd_ps"
    echo "[stand-down] docker compose down failed, but nothing is running" >&2
  fi
fi

mkdir -p "$BACKUP_DIR"
CONF_REMOVED=0
CONF_FILE="$NGINX_CONF_DIR/${DOMAIN_NAME}.conf"
CONF_BACKUP=
if [ -f "$CONF_FILE" ]; then
  TS="$(date '+%Y%m%d-%H%M%S')"
  CONF_BACKUP="$BACKUP_DIR/${DOMAIN_NAME}.conf.removed.$TS"
  echo "[stand-down] Backing up nginx config: $CONF_FILE → $CONF_BACKUP"
  cp "$CONF_FILE" "$CONF_BACKUP"
  rm -f "$CONF_FILE"
  CONF_REMOVED=1
else
  echo "[stand-down] No nginx server config found: $CONF_FILE (nothing to remove)"
fi

restore_conf() {
  if [ "$CONF_REMOVED" -eq 1 ] && [ -n "$CONF_BACKUP" ] && [ -f "$CONF_BACKUP" ]; then
    if ! cp "$CONF_BACKUP" "$CONF_FILE"; then
      echo "[stand-down] ERROR: failed to restore $CONF_FILE" >&2
      exit 1
    fi
    echo "[stand-down] Restored nginx config from $CONF_BACKUP" >&2
  fi
}

if ! sh "$NGINX_TEST"; then
  echo "[stand-down] ERROR: nginx test failed after removing the vhost" >&2
  restore_conf
  exit 1
fi

if ! sh "$NGINX_RELOAD"; then
  echo "[stand-down] ERROR: nginx reload failed" >&2
  restore_conf
  exit 1
fi

echo "[stand-down] Project '$PROJECT' has been stood down:"
if [ "$STATIC_SITE" = "yes" ]; then
  echo "             - No containers (static site)"
elif [ "$CONTAINERS_STOPPED" -eq 1 ]; then
  echo "             - Containers stopped"
else
  echo "             - No containers were running"
fi
if [ "$CONF_REMOVED" -eq 1 ]; then
  echo "             - Nginx server config removed"
else
  echo "             - No nginx server config was installed"
fi
echo "             - Nginx reloaded"
