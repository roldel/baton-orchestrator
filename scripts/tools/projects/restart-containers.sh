#!/bin/sh
# Restart a project's containers using its docker compose file(s).
# - Resolves compose file(s) via the shared helper (auto-detect or
#   DOCKER_COMPOSE_FILES in the project's .env)
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
COMPOSE_CMD="$BASE_DIR/scripts/tools/helpers/compose-cmd.sh"
RESOLVE_HELPER="$BASE_DIR/scripts/tools/helpers/resolve-compose-files.sh"

echo "[restart-containers] Restarting containers for project: $PROJECT (dir: $PROJECT_DIR)"

# --- Basic validation ---
if [ ! -d "$PROJECT_DIR" ]; then
  echo "[restart-containers] ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

if [ ! -f "$COMPOSE_CMD" ]; then
  echo "[restart-containers] ERROR: compose-cmd helper not found: $COMPOSE_CMD" >&2
  exit 1
fi

# --- Log resolved compose files (capture so resolve failure aborts under set -e) ---
if [ -f "$RESOLVE_HELPER" ]; then
  COMPOSE_FILES="$(sh "$RESOLVE_HELPER" "$PROJECT_DIR")"
  echo "[restart-containers] Using compose file(s):"
  printf '%s\n' "$COMPOSE_FILES" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "[restart-containers]   - $f"
  done
fi

# --- Restart containers ---
echo "[restart-containers] docker compose down"
sh "$COMPOSE_CMD" "$PROJECT_DIR" down

echo "[restart-containers] docker compose up -d --build --force-recreate"
sh "$COMPOSE_CMD" "$PROJECT_DIR" up -d --build --force-recreate

echo "[restart-containers] Restart complete for project: $PROJECT"
