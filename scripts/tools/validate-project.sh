#!/bin/sh
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via baton"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

validate_project() {
  proj="$1"
  proj_dir="$PROJECTS_DIR/$proj"
  conf_file="$proj_dir/server.conf"
  env_file="$proj_dir/.env"

  [ -d "$proj_dir" ]  || { echo "ERROR: Project directory not found: $proj_dir" >&2; return 1; }
  [ -f "$conf_file" ] || { echo "ERROR: Missing server.conf in $proj_dir" >&2; return 1; }
  [ -f "$env_file" ]  || { echo "ERROR: Missing .env in $proj_dir (see .env.sample)" >&2; return 1; }

  # Validate required keys and normalizations
  load_dotenv "$env_file" || return 1

  echo "$DOMAIN_NAME" | grep -Eq '^[A-Za-z0-9.-]+$' || {
    echo "ERROR: DOMAIN_NAME looks invalid: $DOMAIN_NAME" >&2; return 1; }

  return 0
}
