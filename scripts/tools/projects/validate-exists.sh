#!/bin/sh
set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"
PROJECT_DIR="/srv/projects/$PROJECT"

echo "Validating project dir: $PROJECT_DIR"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "[validate-exists] ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi
