#!/bin/sh
# Deploy a project by name: validates, renders server conf, restarts project containers,
# ensures certs, installs conf, reloads nginx
set -eu

# --- Collect project name ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 <project-name>" >&2
    exit 1
fi

PROJECT="$1"

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
COMPOSE_FILE="$(sh "$TOOLS_DIR/helpers/detect-compose-file.sh" "$PROJECT_DIR")"
echo "[deploy] Using compose file: $COMPOSE_FILE"

# 3) Env validation
REQUIRED_ENV_VARS="
  DOMAIN_NAME
  DOCKER_NETWORK_SERVICE_ALIAS
  APP_PORT
  DOMAIN_ADMIN_EMAIL
"
sh "$TOOLS_DIR/projects/validate-env.sh" "$PROJECT" $REQUIRED_ENV_VARS

# 4) Render server.conf template
RENDERED_FILE="$(sh "$TOOLS_DIR/projects/render-server-conf.sh" "$PROJECT")"
echo "[deploy] Rendered server config at: $RENDERED_FILE"

# 5) Restart project containers: down → up -d (clean state + apply .env)
sh "$TOOLS_DIR/projects/restart-containers.sh" "$PROJECT"

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