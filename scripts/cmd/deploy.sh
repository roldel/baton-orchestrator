#!/bin/sh
# Deploy a project by name: validates, renders server conf, restarts project containers,
# ensures certs, installs conf, reloads nginx
#
# Usage:
#   ./scripts/cmd/deploy.sh <project-name>
#   ./scripts/cmd/deploy.sh <project-name> --webhook   # also activate webhook after deploy
set -eu

# --- Collect project name ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 <project-name> [--webhook]" >&2
    exit 1
fi

PROJECT="$1"
ACTIVATE_WEBHOOK=0
[ "${2:-}" = "--webhook" ] && ACTIVATE_WEBHOOK=1

BASE_DIR="/opt/baton-orchestrator"
. "$BASE_DIR/scripts/tools/webhook/lock-lib.sh"
baton_hold_webhook_lock "$@"

PROJECT_DIR="/srv/projects/$PROJECT"

TOOLS_DIR="$BASE_DIR/scripts/tools"

ORCHESTRATOR_COMPOSE_FILE="$BASE_DIR/orchestrator/docker-compose.yml"

echo "[deploy] Starting deploy for project: $PROJECT"


# Call the modular steps in order


# 1) Project structure validation
sh "$TOOLS_DIR/projects/validate-exists.sh" "$PROJECT"

# The webhook container (uid 65532) reads this project's .env.
sh "$TOOLS_DIR/projects/grant-webhook-read.sh" "$PROJECT_DIR"

# 2) Project content validation
sh "$TOOLS_DIR/projects/validate-content.sh" "$PROJECT"

# 2b) Static site detection (no compose/container: nginx serves a synced build
# directory instead of proxying to an app)
STATIC_SITE="$(sh "$TOOLS_DIR/projects/detect-static-site.sh" "$PROJECT")"
echo "[deploy] Static site: $STATIC_SITE"

if [ "$STATIC_SITE" != "yes" ]; then
  COMPOSE_FILES="$(sh "$TOOLS_DIR/helpers/resolve-compose-files.sh" "$PROJECT_DIR")"
  echo "[deploy] Using compose file(s):"
  printf '%s\n' "$COMPOSE_FILES" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "[deploy]   - $f"
  done
fi

# 3) Env validation — DOMAIN vars always required; static vs dynamic adds the rest
REQUIRED_ENV_VARS="DOMAIN_NAME DOMAIN_ADMIN_EMAIL"
if [ "$STATIC_SITE" = "yes" ]; then
  REQUIRED_ENV_VARS="$REQUIRED_ENV_VARS STATIC_SOURCE_DIR"
else
  REQUIRED_ENV_VARS="$REQUIRED_ENV_VARS DOCKER_NETWORK_SERVICE_ALIAS APP_PORT"
fi
sh "$TOOLS_DIR/projects/validate-env.sh" "$PROJECT" $REQUIRED_ENV_VARS

# 4) Render server.conf template
RENDERED_FILE="$(sh "$TOOLS_DIR/projects/render-server-conf.sh" "$PROJECT")"
echo "[deploy] Rendered server config at: $RENDERED_FILE"

# 5) Deploy the site's actual content.
# Static: publish STATIC_SOURCE_DIR and do not start containers.
# Dynamic: start containers. If STATIC_SOURCE_DIR is also set, publish that
# directory first (same release-symlink copy as a static site) so server.conf
# can serve it from /srv/shared-files/<domain>/site. Sync runs before the
# container restart: a missing build fails without taking the app down.
# Read the variable in a subshell so this .env cannot clobber the script.
STATIC_SOURCE_DIR="$(
  set +eu
  . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
  if load_env_safe "$PROJECT_DIR/.env"; then
    printf '%s' "${STATIC_SOURCE_DIR:-}"
  fi
)"

PREV_STATIC_RELEASE=""
STATIC_SITE_LINK=""
if [ "$STATIC_SITE" = "yes" ] || [ -n "$STATIC_SOURCE_DIR" ]; then
  _deploy_site_key="$(sh "$BASE_DIR/scripts/tools/helpers/compute-site-key.sh" "$PROJECT")"
  STATIC_SITE_LINK="${BATON_SHARED_FILES_ROOT:-/srv/shared-files}/$_deploy_site_key/site"
  if [ -L "$STATIC_SITE_LINK" ]; then
    PREV_STATIC_RELEASE="$(readlink "$STATIC_SITE_LINK" 2>/dev/null || true)"
  fi
  SYNCED_DIR="$(sh "$TOOLS_DIR/static/sync-static-site.sh" "$PROJECT")"
  echo "[deploy] Synced static files to: $SYNCED_DIR"
fi

if [ "$STATIC_SITE" != "yes" ]; then
  if ! sh "$TOOLS_DIR/projects/restart-containers.sh" "$PROJECT"; then
    if [ -n "$PREV_STATIC_RELEASE" ] && [ -n "$STATIC_SITE_LINK" ]; then
      . "$TOOLS_DIR/static/publish-lib.sh"
      baton_atomic_symlink "$PREV_STATIC_RELEASE" "$STATIC_SITE_LINK"
      echo "[deploy] Restored static files to $PREV_STATIC_RELEASE" >&2
    fi
    echo "[deploy] ERROR: container restart failed" >&2
    exit 1
  fi
fi

# 6) SSL: check certs; if missing → issue process for new certs
sh "$TOOLS_DIR/ssl/ensure-certs.sh" "$PROJECT"

# 7) Install the rendered server block into nginx/conf.d
INSTALLED_CONF="$(sh "$TOOLS_DIR/projects/install-server-conf.sh" "$PROJECT")"
echo "[deploy] Installed nginx server config at: $INSTALLED_CONF"

# 8) Syntax check full nginx config through running container
sh "$TOOLS_DIR/nginx/test-config.sh"

# 9) Reload Nginx
sh "$TOOLS_DIR/nginx/reload.sh"

echo "[deploy] Completed for project: $PROJECT"

# 10) Optionally activate webhook
if [ "$ACTIVATE_WEBHOOK" -eq 1 ]; then
    echo "------------------------------------------------------------"
    echo "[deploy] --webhook flag set — activating webhook..."

    # Read the webhook variables in a subshell so the project file cannot replace BASE_DIR.
    WEBHOOK_URL="$(
        set +eu
        . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
        if load_env_safe "$PROJECT_DIR/.env"; then
            printf '%s' "${WEBHOOK_URL:-}"
        fi
    )"
    PAYLOAD_SIGNATURE="$(
        set +eu
        . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
        if load_env_safe "$PROJECT_DIR/.env"; then
            printf '%s' "${PAYLOAD_SIGNATURE:-}"
        fi
    )"

    if [ -z "$WEBHOOK_URL" ] || [ -z "$PAYLOAD_SIGNATURE" ]; then
        echo "[deploy] ERROR: --webhook requested but WEBHOOK_URL or PAYLOAD_SIGNATURE" >&2
        echo "[deploy]        is not set in $PROJECT_DIR/.env. Skipping webhook activation." >&2
        exit 1
    fi

    sh "$BASE_DIR/scripts/cmd/webhook-activate.sh" "$PROJECT"
    echo "[deploy] Webhook activated."
fi