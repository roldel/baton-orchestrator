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

# 1) .env
[ -f "$PROJ_DIR/.env" ] || { echo "ERROR: Missing $PROJ_DIR/.env" >&2; REQS_OK=0; }

# 2) docker compose file (accept either)
if [ ! -f "$PROJ_DIR/docker-compose.yml" ] && [ ! -f "$PROJ_DIR/template-docker-compose.yml" ]; then
  echo "ERROR: Missing docker-compose file (docker-compose.yml or template-docker-compose.yml) in $PROJ_DIR" >&2
  REQS_OK=0
fi

# 3) server.conf template
[ -f "$PROJ_DIR/server.conf" ] || { echo "ERROR: Missing $PROJ_DIR/server.conf" >&2; REQS_OK=0; }

[ "$REQS_OK" -eq 1 ] || { echo "[project-validator] ❌ Validation failed" >&2; exit 1; }

echo "[project-validator] ✅ Project structure OK"
