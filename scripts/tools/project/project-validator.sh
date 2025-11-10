#!/bin/sh
# Validate that a project exists with required files
# Usage: project-validator.sh <project-name>
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
PROJ_DIR="$ROOT/projects/$PROJECT"

echo "[project-validator] Checking $PROJ_DIR"

[ -d "$PROJ_DIR" ] || { echo "ERROR: Project directory not found: $PROJ_DIR" >&2; exit 1; }

REQS_OK=1

# 1) .env file is always required
ENV_FILE="$PROJ_DIR/.env"
[ -f "$ENV_FILE" ] || { echo "ERROR: Missing $ENV_FILE" >&2; REQS_OK=0; }

# Load project-specific .env file to check DOCKER_COMPOSE flag
# Only load if the .env file exists, to avoid errors if REQS_OK is already 0
if [ "$REQS_OK" -eq 1 ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

# 2) Docker Compose file check (conditional based on DOCKER_COMPOSE flag)
# If DOCKER_COMPOSE is explicitly set to NO, skip this check
if [ "${DOCKER_COMPOSE:-YES}" = "NO" ]; then
  echo "[project-validator] DOCKER_COMPOSE is set to NO for project $PROJECT. Skipping Docker Compose file check."
else
  if [ ! -f "$PROJ_DIR/docker-compose.yml" ] && [ ! -f "$PROJ_DIR/template-docker-compose.yml" ]; then
    echo "ERROR: Missing docker-compose file (docker-compose.yml or template-docker-compose.yml) in $PROJ_DIR" >&2
    REQS_OK=0
  fi
fi

# 3) server.conf template is always required
[ -f "$PROJ_DIR/server.conf" ] || { echo "ERROR: Missing $PROJ_DIR/server.conf" >&2; REQS_OK=0; }

[ "$REQS_OK" -eq 1 ] || { echo "[project-validator] ❌ Validation failed" >&2; exit 1; }

echo "[project-validator] ✅ Project structure OK"