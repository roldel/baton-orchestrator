#!/bin/sh
set -euo pipefail

JOB_NAME="my-daily-cronjob"
JOB_TARGET_PATH="/etc/periodic/daily/${JOB_NAME}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root." >&2
  exit 1
fi

if [ -f "${JOB_TARGET_PATH}" ]; then
  rm -f "${JOB_TARGET_PATH}"
  echo "Removed ${JOB_TARGET_PATH}"
else
  echo "No job found at ${JOB_TARGET_PATH} (nothing to remove)."
fi

# No restart needed; the file is gone, so it simply won't run next time.
# If you want to be extra explicit, you could do:
# rc-service crond restart >/dev/null 2>&1 || true
