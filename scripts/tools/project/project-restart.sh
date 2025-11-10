#!/bin/sh
# Restart project Docker Compose: down → up -d
# Ensures clean state and latest env/config
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
PROJ_DIR="$ROOT/projects/$PROJECT"

# Find compose file
if [ -f "$PROJ_DIR/docker-compose.yml" ]; then
  COMPOSE_FILE="$PROJ_DIR/docker-compose.yml"
elif [ -f "$PROJ_DIR/template-docker-compose.yml" ]; then
  COMPOSE_FILE="$PROJ_DIR/template-docker-compose.yml"
else
  echo "ERROR: No docker-compose file in $PROJ_DIR" >&2
  exit 1
fi

echo "[project-restart] Stopping old containers (if any)..."
docker compose -f "$COMPOSE_FILE" down || true

echo "[project-restart] Starting project: $PROJECT"
docker compose -f "$COMPOSE_FILE" up -d

echo "[project-restart] Project $PROJECT is up"