#!/bin/sh
# Restart project Docker Compose: down → up -d
# Ensures clean state and latest env/config
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
PROJ_DIR="$ROOT/projects/$PROJECT"

# Load project-specific .env file
ENV_FILE="$PROJ_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

# Check for DOCKER_COMPOSE=NO flag
if [ "${DOCKER_COMPOSE:-YES}" = "NO" ]; then
  echo "[project-restart] DOCKER_COMPOSE is set to NO for project $PROJECT. Skipping Docker Compose operations."
  exit 0 # Exit successfully, as per the explicit instruction
fi

# Find compose file (original logic)
if [ -f "$PROJ_DIR/docker-compose.yml" ]; then
  COMPOSE_FILE="$PROJ_DIR/docker-compose.yml"
elif [ -f "$PROJ_DIR/template-docker-compose.yml" ]; then
  COMPOSE_FILE="$PROJ_DIR/template-docker-compose.yml"
else
  echo "ERROR: No docker-compose file found for project $PROJECT (and DOCKER_COMPOSE is not set to NO)" >&2
  exit 1
fi

echo "[project-restart] Stopping old containers (if any)..."
docker compose -f "$COMPOSE_FILE" down || true

echo "[project-restart] Starting project: $PROJECT"
docker compose -f "$COMPOSE_FILE" up -d

echo "[project-restart] Project $PROJECT is up"