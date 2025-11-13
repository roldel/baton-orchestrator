#!/bin/sh
# Restart a project's containers using its docker compose file.
# - Detects compose file via the shared helper
# - Runs `docker compose down` then `up -d --build --force-recreate`
# - Runs from the project directory so .env is picked up automatically

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
COMPOSE_HELPER="$BASE_DIR/scripts/tools/helpers/detect-compose-file.sh"

echo "[restart-containers] Restarting containers for project: $PROJECT (dir: $PROJECT_DIR)"

# --- Basic validation ---
if [ ! -d "$PROJECT_DIR" ]; then
  echo "[restart-containers] ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

if [ ! -x "$COMPOSE_HELPER" ]; then
  echo "[restart-containers] ERROR: detect-compose-file helper not found or not executable: $COMPOSE_HELPER" >&2
  exit 1
fi

# --- Detect compose file (absolute path) ---
COMPOSE_FILE="$(sh "$COMPOSE_HELPER" "$PROJECT_DIR")"
COMPOSE_DIR="$(dirname "$COMPOSE_FILE")"

echo "[restart-containers] Using compose file: $COMPOSE_FILE"

# --- Restart containers ---
# We `cd` into the compose dir so:
#   - docker compose picks up .env from there
#   - any relative paths in the compose file are correct
cd "$COMPOSE_DIR"

echo "[restart-containers] docker compose down"
docker compose -f "$COMPOSE_FILE" down

echo "[restart-containers] docker compose up -d --build --force-recreate"
docker compose -f "$COMPOSE_FILE" up -d --build --force-recreate

echo "[restart-containers] Restart complete for project: $PROJECT"
