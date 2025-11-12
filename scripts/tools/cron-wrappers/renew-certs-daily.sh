#!/bin/sh
# baton-ssl-renewal.sh — cron job for daily SSL cert renewal
# Installed to /etc/periodic/daily/baton-ssl-renewal by scripts/setup.sh
set -eu

# Adjust this if you *really* install baton somewhere else.
BASE_DIR="/opt/baton-orchestrator"
RENEW_SCRIPT="$BASE_DIR/scripts/cmd/renew-all-certs.sh"
LOG_FILE="$BASE_DIR/logs/cert-renewal.log"

# Cron usually has a very minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Basic sanity checks
if [ ! -x "$RENEW_SCRIPT" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $RENEW_SCRIPT not found or not executable" >&2
  exit 1
fi

# Ensure log directory exists
LOG_DIR="$(dirname "$LOG_FILE")"
mkdir -p "$LOG_DIR" 2>/dev/null || {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Cannot create log dir: $LOG_DIR" >&2
  exit 1
}

# Run the renewal script; all output goes to the log.
# Any non-zero exit from the renewal script will bubble up to cron.
echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- Starting renew-all-certs.sh ---" >>"$LOG_FILE" 2>&1
"$RENEW_SCRIPT" >>"$LOG_FILE" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- Finished renew-all-certs.sh (rc=$?) ---" >>"$LOG_FILE" 2>&1
