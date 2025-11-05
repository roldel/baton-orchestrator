#!/bin/sh
. "$(dirname "$0")/../env-setup.sh"

validate_project() {
  proj="$1"
  proj_dir="$PROJECTS_DIR/$proj"
  conf_file="$proj_dir/server.conf"

  if [ ! -d "$proj_dir" ]; then
    echo "ERROR: Project directory not found: $proj_dir" >&2
    return 1
  fi
  if [ ! -f "$conf_file" ]; then
    echo "ERROR: Missing server.conf in $proj_dir" >&2
    return 1
  fi

  return 0
}
