#!/bin/sh
set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

# PROJECT is interpolated directly into PROJECT_DIR below and into every
# other cmd/ script's own /srv/projects/$PROJECT path. This script is the
# first validation step called by deploy.sh, stand-down.sh, respawn.sh,
# webhook-activate.sh and webhook-deactivate.sh, so rejecting a path-like
# project name here — before any of those build a path from it — stops e.g.
# "../../etc" (or an absolute path) from resolving outside /srv/projects.
case "$PROJECT" in
  ''|.|..)
    echo "[validate-exists] ERROR: invalid project name: '$PROJECT'" >&2
    exit 1
    ;;
  */*)
    echo "[validate-exists] ERROR: project name cannot contain '/': '$PROJECT'" >&2
    exit 1
    ;;
esac

PROJECT_DIR="/srv/projects/$PROJECT"

echo "Validating project dir: $PROJECT_DIR"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "[validate-exists] ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi
