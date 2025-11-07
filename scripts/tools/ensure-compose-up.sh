#!/bin/sh
# ensure-compose-up.sh — Ensure the project's Docker Compose stack is running (no templates)
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via baton"; exit 1; }
. "$BASE_DIR/env-setup.sh"  # provides PROJECTS_DIR, etc.

ensure_compose_up() {
  proj="$1"
  proj_dir="$PROJECTS_DIR/$proj"
  compose_file="$proj_dir/docker-compose.yml"

  # Require a real docker-compose.yml (no templates in pro projects)
  if [ ! -f "$compose_file" ]; then
    echo "ERROR: Missing $compose_file" >&2
    return 1
  fi

  echo "Checking Docker Compose stack for project: $proj"

  # If any service is running, do nothing; otherwise bring the stack up.
  if (cd "$proj_dir" && docker compose ps --status=running -q | grep -q .); then
    echo "✅ Project stack is already running."
    return 0
  fi

  echo "Starting project stack..."
  if (cd "$proj_dir" && docker compose up -d); then
    echo "✅ Project stack is now up."
    return 0
  else
    echo "❌ Failed to start project stack." >&2
    return 1
  fi
}
