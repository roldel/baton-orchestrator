#!/bin/sh
# Deploy a project by name: validates, renders server conf, restarts project containers,
# ensures certs, installs conf, reloads nginx
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

# Resolve BASE_DIR then load shared env
THIS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "$THIS_DIR/../.." && pwd)"
export BASE_DIR
# shellcheck disable=SC1091
. "$BASE_DIR/env-setup.sh"

COMPOSE_FILE="$ORCHESTRATOR_DIR/docker-compose.yml"

echo "[deploy] Starting deploy for project: $PROJECT"
echo "[deploy] BASE_DIR=$BASE_DIR"

# 1) Project structure validation
"$SCRIPT_DIR/tools/project/project-validator.sh" "$PROJECT"

# 2) Env validation
"$SCRIPT_DIR/tools/project/env-validator.sh" "$PROJECT"

# 3) Render server.conf → orchestrator/server-confs/<project>.conf
"$SCRIPT_DIR/tools/project/render-conf-server-file.sh" "$PROJECT"

# 4) Restart project containers: down → up -d (clean state + apply .env)
"$SCRIPT_DIR/tools/project/project-restart.sh" "$PROJECT"

# 5) SSL: check certs; if missing/expiring/aliases mismatch → issue
if ! "$SCRIPT_DIR/tools/ssl-management/ssl-certs-checker.sh" "$PROJECT"; then
  echo "[deploy] SSL not valid; running initial issuance…"
  "$SCRIPT_DIR/tools/ssl-management/initial-issual.sh" "$PROJECT"
fi

# 6) Install the rendered server block into nginx/conf.d
"$SCRIPT_DIR/tools/nginx/add-server-conf.sh" "$PROJECT"

# 7) Syntax check full nginx config through running container
"$SCRIPT_DIR/tools/project/server-syntax-check.sh"

# 8) Reload Nginx
"$SCRIPT_DIR/tools/nginx/server-reload.sh"

echo "[deploy] Completed for project: $PROJECT"