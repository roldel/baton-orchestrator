#!/bin/sh
# Install the rendered server config for a project into nginx/conf.d
# Source:  /opt/baton-orchestrator/tmp/rendered/${SITE_KEY}.conf
# Target:  /opt/baton-orchestrator/orchestrator/nginx/conf.d/${SITE_KEY}.conf
#   SITE_KEY = $DOMAIN_NAME

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"
TMP_DIR="$BASE_DIR/tmp/rendered"
NGINX_CONF_DIR="$BASE_DIR/orchestrator/nginx/conf.d"
BACKUP_DIR="$BASE_DIR/tmp/nginx-backups"

echo "[install-server-conf] Installing server config for project: $PROJECT (dir: $PROJECT_DIR)"

# --- Basic validation ---
if [ ! -d "$PROJECT_DIR" ]; then
  echo "[install-server-conf] ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "[install-server-conf] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

SITE_KEY="$(sh "$BASE_DIR/scripts/tools/helpers/compute-site-key.sh" "$PROJECT")"

SRC="$TMP_DIR/${SITE_KEY}.conf"
DEST="$NGINX_CONF_DIR/${SITE_KEY}.conf"

if [ ! -f "$SRC" ]; then
  echo "[install-server-conf] ERROR: Rendered config not found: $SRC" >&2
  echo "  Did you run render-server-conf.sh first?" >&2
  exit 1
fi

# The rendered file is about to join the shared ingress. Reject it before copy.
DOMAIN_ALIASES="$(
  set +eu
  . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${DOMAIN_ALIASES:-}"
  fi
)"
UPSTREAM="$(
  set +eu
  . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${DOCKER_NETWORK_SERVICE_ALIAS:-}"
  fi
)"
APP_PORT="$(
  set +eu
  . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${APP_PORT:-}"
  fi
)"
. "$BASE_DIR/scripts/tools/helpers/check-domain-aliases.sh"
if ! DOMAIN_ALIASES="$(baton_normalize_domain_aliases "$DOMAIN_ALIASES")"; then
  echo "[install-server-conf] ERROR: DOMAIN_ALIASES rejected" >&2
  exit 1
fi
. "$BASE_DIR/scripts/tools/helpers/nginx-conf-allow.sh"
if ! baton_check_rendered_conf "$SRC" "$SITE_KEY" "$DOMAIN_ALIASES" "$SITE_KEY" "$UPSTREAM" "$APP_PORT"; then
  echo "[install-server-conf] ERROR: rendered server config rejected" >&2
  exit 1
fi

mkdir -p "$NGINX_CONF_DIR"
mkdir -p "$BACKUP_DIR"

# --- Optional: backup existing dest if present ---
if [ -f "$DEST" ]; then
  TS="$(date '+%Y%m%d-%H%M%S')"
  BACKUP_FILE="$BACKUP_DIR/${SITE_KEY}.conf.$TS"
  echo "[install-server-conf] Backing up existing config: $DEST → $BACKUP_FILE"
  cp -f "$DEST" "$BACKUP_FILE"
fi

echo "[install-server-conf] Installing $SRC → $DEST"
cp -f "$SRC" "$DEST"

echo "[install-server-conf] Installation complete: $DEST"

# Atomic: this file is now live in conf.d, so validate the full nginx config
# before considering the install done. A broken config left in place here
# wouldn't break the *running* nginx (no reload has happened yet), but a
# later full restart (host reboot, orchestrator-compose-respawn.sh) would
# then fail to start nginx at all — taking down every project, not just
# this one — so roll back to the pre-install state on failure instead.
if ! sh "$BASE_DIR/scripts/tools/nginx/test-config.sh"; then
  echo "[install-server-conf] ERROR: Nginx configuration test failed after installing $DEST" >&2
  if [ -n "${BACKUP_FILE:-}" ] && [ -f "$BACKUP_FILE" ]; then
    echo "[install-server-conf] Restoring previous config from backup: $BACKUP_FILE" >&2
    cp -f "$BACKUP_FILE" "$DEST"
  else
    echo "[install-server-conf] No previous config existed — removing broken file: $DEST" >&2
    rm -f "$DEST"
  fi
  exit 1
fi

# Print the final path (for logs / tooling if needed)
echo "$DEST"
