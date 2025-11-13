#!/bin/sh
# Validate project content:
# - .env present
# - server.conf present
# - a docker compose file present (with flexible naming)
set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"
PROJECT_DIR="/srv/projects/$PROJECT"
BASE_DIR="/opt/baton-orchestrator"
COMPOSE_HELPER="$BASE_DIR/scripts/tools/helpers/detect-compose-file.sh"

echo "[validate-content] Validating content for project: $PROJECT_DIR"

# --- Basic dir check (defensive; validate-project should already have done this) ---
if [ ! -d "$PROJECT_DIR" ]; then
  echo "[validate-content] ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

# --- .env file ---
ENV_FILE="$PROJECT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "[validate-content] ERROR: Missing .env file: $ENV_FILE" >&2
  echo "             (You can base it on .env.sample if needed.)" >&2
  exit 1
fi

# --- server.conf template ---
SERVER_CONF="$PROJECT_DIR/server.conf"
if [ ! -f "$SERVER_CONF" ]; then
  echo "[validate-content] ERROR: Missing server.conf file: $SERVER_CONF" >&2
  exit 1
fi

# --- Docker Compose file (via shared helper) ---
if [ ! -x "$COMPOSE_HELPER" ]; then
  echo "[validate-content] ERROR: detect-compose-file helper not found or not executable: $COMPOSE_HELPER" >&2
  exit 1
fi

COMPOSE_FILE="$(sh "$COMPOSE_HELPER" "$PROJECT_DIR")"
echo "[validate-content] Found compose file: $COMPOSE_FILE"
echo "[validate-content] Project content validation OK."
