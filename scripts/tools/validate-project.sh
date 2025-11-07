#!/bin/sh
# scripts/tools/validate-project.sh
set -eu

validate_project() {
  proj="$1"
  proj_dir="$PROJECTS_DIR/$proj"
  env_file="$proj_dir/.env"
  conf_file="$proj_dir/server.conf"

  [ -d "$proj_dir" ] || { echo "ERROR: Project directory not found: $proj_dir" >&2; exit 1; }
  [ -f "$conf_file" ] || { echo "ERROR: Missing server.conf in $proj_dir" >&2; exit 1; }
  [ -f "$env_file" ] || { echo "ERROR: Missing .env in $proj_dir (see .env.sample)" >&2; exit 1; }

  # Load and validate required .env fields
  . "$SCRIPT_DIR/tools/load-dotenv.sh"
  if ! load_dotenv "$env_file" 2>/dev/null; then
    echo "ERROR: Failed to parse .env or missing required fields." >&2
    echo "Required: DOMAIN_NAME, DOCKER_NETWORK_SERVICE_ALIAS, APP_PORT" >&2
    exit 1
  fi

  echo "Validation passed for project: $proj"
}