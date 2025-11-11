# File: /home/x/Code/baton-orchestrator/scripts/cron-wrappers/renew-certs-daily.sh
#!/bin/sh
# This wrapper script is called by crond to manage SSL certificate renewal.
# It ensures the correct environment is set for the actual renewal script.
#
# {{BATON_PROJECT_ROOT}} is a placeholder that will be replaced by setup.sh
# with the absolute path of the baton-orchestrator project.

# --- IMPORTANT: This path will be replaced during setup.sh execution ---
BATON_PROJECT_ROOT="{{BATON_PROJECT_ROOT}}"

# --- Configure the environment for the renewal script ---
export BASE_DIR="$BATON_PROJECT_ROOT"
# Ensure common binaries are in PATH, as cron's PATH can be minimal
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Define the log file for this specific cron job
LOG_FILE="$BASE_DIR/logs/cert-renewal.log"

# --- Ensure log directory exists before attempting to write to it ---
mkdir -p "$(dirname "$LOG_FILE")" || {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Failed to create log directory for cron job." >&2
  exit 1
}

# --- Execute the actual SSL renewal script ---
# `exec` replaces the current shell with the executed script,
# ensuring the exit status of renew-all-certs.sh is the cron job's exit status.
# All output (stdout and stderr) is redirected to the log file.
exec "$BASE_DIR/scripts/cmd/renew-all-certs.sh" >> "$LOG_FILE" 2>&1