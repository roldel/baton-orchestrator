#!/bin/sh
# Group 65532 can traverse directories under the given root and read regular
# .env files. Other files stay as they are. Symlinks are not followed.
#
# Usage: grant-webhook-read.sh <directory>

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <directory>" >&2
  exit 1
fi

ROOT=$1
if [ ! -d "$ROOT" ]; then
  echo "[grant-webhook-read] no directory $ROOT" >&2
  exit 0
fi

_gwr_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$_gwr_dir/../webhook/task-lib.sh"

if [ "$(id -u)" -eq 0 ]; then
  if ! baton_ensure_webhook_user; then
    echo "[grant-webhook-read] ERROR: uid 65532 is not available" >&2
    exit 1
  fi
fi

find "$ROOT" -type d -exec chgrp 65532 {} + -exec chmod g+rx {} +
find "$ROOT" -name .env -type f -exec chgrp 65532 {} + -exec chmod g+r {} +
