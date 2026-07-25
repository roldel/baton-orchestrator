#!/bin/sh
# Detects whether a project is a static site from its .env.
# STATIC_SITE=no (default/unset)  -> today's app-container behavior
# STATIC_SITE=yes                 -> no compose file/container; nginx serves
#                                     a synced build directory directly.
#
# Prints the resolved value to stdout. Exits with error on an unknown value.

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "[detect-static-site] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$ENV_FILE"

STATIC_SITE="${STATIC_SITE:-no}"

case "$STATIC_SITE" in
  yes|no) ;;
  *)
    echo "[detect-static-site] ERROR: Unknown STATIC_SITE '$STATIC_SITE' in $ENV_FILE (expected: yes, no)" >&2
    exit 1
    ;;
esac

echo "$STATIC_SITE"
