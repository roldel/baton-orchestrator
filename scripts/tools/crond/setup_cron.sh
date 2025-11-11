#!/bin/sh
set -euo pipefail

# --- config ---
JOB_NAME="my-daily-cronjob"            # Filename under /etc/periodic/daily (no dots/spaces)
JOB_SOURCE="./cronjob.sh"              # Path to your repo script
JOB_TARGET_DIR="/etc/periodic/daily"
JOB_TARGET_PATH="${JOB_TARGET_DIR}/${JOB_NAME}"

# --- root check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root." >&2
  exit 1
fi

# --- ensure cron as a managed service (idempotent) ---
# busybox -> provides /usr/sbin/crond
# busybox-openrc -> provides /etc/init.d/crond (OpenRC service script)
echo "Ensuring cron service and OpenRC integration are installed..."
apk add --no-cache busybox busybox-openrc >/dev/null

# --- sanity: required commands now present ---
for cmd in crond rc-update rc-service install; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found after install." >&2
    exit 1
  fi
done

# --- prepare target dir ---
install -d -m 755 "${JOB_TARGET_DIR}"

# --- validate and install job ---
if [ ! -f "${JOB_SOURCE}" ]; then
  echo "Job source not found: ${JOB_SOURCE}" >&2
  exit 1
fi

# Use 'install' for atomic copy + perms
install -m 755 "${JOB_SOURCE}" "${JOB_TARGET_PATH}"

# --- enable and start crond (safe if already done) ---
rc-update add crond default >/dev/null 2>&1 || true
rc-service crond start >/dev/null 2>&1 || true

echo "Installed: ${JOB_TARGET_PATH}"
echo "Cron is enabled and running."
echo "No crond reload required; /etc/periodic/daily jobs are run automatically at the daily window."

# --- optional quick verification (uncomment to run daily bucket now) ---
# run-parts "${JOB_TARGET_DIR}" && echo "Ran daily bucket once for quick test."
# tail -n +1 /root/cron-test.log || true
 