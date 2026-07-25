#!/bin/sh
# Computes the SITE_KEY used to namespace nginx conf.d filenames and
# shared-files destinations for a project: SITE_KEY = $DOMAIN_NAME
#
# Prints the SITE_KEY to stdout.

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "[compute-site-key] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$ENV_FILE"

if [ -z "${DOMAIN_NAME:-}" ]; then
  echo "[compute-site-key] ERROR: DOMAIN_NAME must be set in $ENV_FILE" >&2
  exit 1
fi
echo "$DOMAIN_NAME"
