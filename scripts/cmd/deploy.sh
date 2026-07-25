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

PROJECT_DIR="/srv/projects/$PROJECT"

TOOLS_DIR="$BASE_DIR/scripts/tools"

ORCHESTRATOR_COMPOSE_FILE="$BASE_DIR/orchestrator/docker-compose.yml"

echo "[deploy] Starting deploy for project: $PROJECT"


# Call the modular steps in order


# 1) Project structure validation
sh "$TOOLS_DIR/projects/validate-exists.sh" "$PROJECT"

# 2) Project content validation
sh "$TOOLS_DIR/projects/validate-content.sh" "$PROJECT"

# 2b) Static site detection (no compose/container: nginx serves a synced build
# directory instead of proxying to an app)
STATIC_SITE="$(sh "$TOOLS_DIR/projects/detect-static-site.sh" "$PROJECT")"
echo "[deploy] Static site: $STATIC_SITE"

if [ "$STATIC_SITE" != "yes" ]; then
  COMPOSE_FILE="$(sh "$TOOLS_DIR/helpers/detect-compose-file.sh" "$PROJECT_DIR")"
  echo "[deploy] Using compose file: $COMPOSE_FILE"
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

# 5) Deploy the site's actual content: sync built static files, or restart
# the project's containers (down → up -d, clean state + apply .env)
if [ "$STATIC_SITE" = "yes" ]; then
  SYNCED_DIR="$(sh "$TOOLS_DIR/static/sync-static-site.sh" "$PROJECT")"
  echo "[deploy] Synced static site to: $SYNCED_DIR"
else
  sh "$TOOLS_DIR/projects/restart-containers.sh" "$PROJECT"
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

    # Verify the required webhook vars are present before attempting activation
    # shellcheck source=/dev/null
    . "$PROJECT_DIR/.env"
    WEBHOOK_URL="${WEBHOOK_URL:-}"
    PAYLOAD_SIGNATURE="${PAYLOAD_SIGNATURE:-}"

    if [ -z "$WEBHOOK_URL" ] || [ -z "$PAYLOAD_SIGNATURE" ]; then
        echo "[deploy] ERROR: --webhook requested but WEBHOOK_URL or PAYLOAD_SIGNATURE" >&2
        echo "[deploy]        is not set in $PROJECT_DIR/.env. Skipping webhook activation." >&2
        exit 1
    fi

    sh "$BASE_DIR/scripts/cmd/webhook-activate.sh" "$PROJECT"
    echo "[deploy] Webhook activated."
fi