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
BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "[compute-site-key] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

# Loaded via load_env_safe, not sourced directly: see that file's header for
# why (a project's own .env sourced directly as shell code is arbitrary
# command execution the instant an unquoted value contains e.g. `;`).
. "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
load_env_safe "$ENV_FILE"

if [ -z "${DOMAIN_NAME:-}" ]; then
  echo "[compute-site-key] ERROR: DOMAIN_NAME must be set in $ENV_FILE" >&2
  exit 1
fi

# SITE_KEY (= DOMAIN_NAME) is used as a path component by install-server-conf.sh,
# sync-static-site.sh and render-server-conf.sh. Without this check, a project's
# own .env could set DOMAIN_NAME to something like "../../../../etc/cron.d/pwn"
# and have those scripts write attacker-chosen content outside their intended
# directory, with the orchestrator's (root) privileges.
case "$DOMAIN_NAME" in
  .|..)
    echo "[compute-site-key] ERROR: DOMAIN_NAME cannot be '.' or '..'" >&2
    exit 1
    ;;
esac
case "$DOMAIN_NAME" in
  *[!A-Za-z0-9.-]*)
    echo "[compute-site-key] ERROR: DOMAIN_NAME contains characters unsafe for use as a path component/hostname (only letters, digits, '.', '-' are allowed): $DOMAIN_NAME" >&2
    exit 1
    ;;
esac

echo "$DOMAIN_NAME"
