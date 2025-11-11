#!/bin/sh
# Irreversible cleanup; run as root
set -eu

# --- Root Check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root." >&2
  exit 1
fi

# Resolve repo root (robust across symlinks)
# Using realpath if available, otherwise fallback
if command -v realpath >/dev/null 2>&1; then
  REAL_PATH=$(realpath "$0")
else
  # Fallback for systems without realpath (e.g., some minimal Alpine setups)
  REAL_PATH=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
fi
REAL_DIR=$(CDPATH= cd -- "$(dirname -- "$REAL_PATH")" && pwd)
BASE_DIR=$(CDPATH= cd -- "$REAL_DIR/.." && pwd)

echo "Cleaning baton-orchestrator from: $BASE_DIR"
echo "THIS WILL DELETE ALL CONFIGS, CERTS, AND SHARED FILES!"
printf "Type YES to continue: "
read -r confirm
[ "$confirm" != "YES" ] && { echo "Aborted."; exit 1; }

COMPOSE_FILE="$BASE_DIR/orchestrator/docker-compose.yml"
# Define paths for new components from setup.sh
CRON_WRAPPER_DEST="/etc/periodic/daily/baton-ssl-renewal"
INIT_D_SERVICE_FILE="/etc/init.d/baton-webhook"
BATON_WEBHOOK_LOG_FILE="/var/log/baton-webhook.log"
OLD_WEBHOOK_PID_FILE="$BASE_DIR/.webhook-watcher.pid" # Keep for compatibility, though OpenRC manages PID now

# -------------------------------
# 1. Stop and disable baton-webhook OpenRC service
# -------------------------------
if [ -f "$INIT_D_SERVICE_FILE" ]; then
  echo "[cleanup] Stopping and disabling baton-webhook service…"
  # Use 'stop' command of the service script
  if rc-service baton-webhook status >/dev/null 2>&1; then
    rc-service baton-webhook stop || true
  fi
  # Remove from default runlevels
  if rc-update show | grep -q "baton-webhook"; then
    rc-update del "baton-webhook" "default" || true
  fi
  rm -f "$INIT_D_SERVICE_FILE"
  echo "[cleanup] Removed $INIT_D_SERVICE_FILE"
fi
# Remove the associated log file
if [ -f "$BATON_WEBHOOK_LOG_FILE" ]; then
  rm -f "$BATON_WEBHOOK_LOG_FILE"
  echo "[cleanup] Removed $BATON_WEBHOOK_LOG_FILE"
fi

# Compatibility: Remove old webhook inotify watcher PID file if it exists
if [ -f "$OLD_WEBHOOK_PID_FILE" ]; then
    PID=$(cat "$OLD_WEBHOOK_PID_FILE")
    echo "[cleanup] Stopping old webhook watcher (PID: $PID) if still running…"
    kill "$PID" 2>/dev/null || true
    rm -f "$OLD_WEBHOOK_PID_FILE"
fi

# -------------------------------
# 2. Remove SSL Renewal Cron Job
# -------------------------------
if [ -f "$CRON_WRAPPER_DEST" ]; then
  echo "[cleanup] Removing SSL renewal cron job: $CRON_WRAPPER_DEST"
  rm -f "$CRON_WRAPPER_DEST"
fi
# Also remove the specific log file for cert renewal if it exists
if [ -f "$BASE_DIR/logs/cert-renewal.log" ]; then
  rm -f "$BASE_DIR/logs/cert-renewal.log"
  echo "[cleanup] Removed $BASE_DIR/logs/cert-renewal.log"
fi


# -------------------------------
# 3. Stop Docker stack
# -------------------------------
if [ -f "$COMPOSE_FILE" ] && docker info >/dev/null 2>&1; then
  echo "Stopping orchestrator services (nginx, webhook, etc.)..."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans || true
else
  echo "Orchestrator Docker Compose not found or Docker not running; skipping stack down."
fi

# -------------------------------
# 4. Remove Docker network
# -------------------------------
if docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
  echo "Removing network: internal_proxy_pass_network"
  docker network rm internal_proxy_pass_network || true
else
  echo "Docker network internal_proxy_pass_network not found; skipping removal."
fi

# -------------------------------
# 5. Remove orchestrator data directories
# -------------------------------
echo "Removing orchestrator data directories..."
rm -rf \
  "$BASE_DIR/orchestrator/data" \
  "$BASE_DIR/orchestrator/server-confs" \
  "$BASE_DIR/orchestrator/webhook-redeploy-instruct" \
  "$BASE_DIR/logs" \
  2>/dev/null || true

# -------------------------------
# 6. Remove shared files directory (if created by setup)
# -------------------------------
if [ -d /shared-files ]; then
  echo "Removing /shared-files (all static/media)"
  # Be careful here: only remove if it's empty or you're absolutely sure
  # it was created by baton and only contains baton-related files.
  # For safety, you might want to only remove its *contents* or ask user confirmation.
  # Given the prompt, we'll assume a full removal is intended.
  rm -rf /shared-files/*
  rmdir /shared-files 2>/dev/null || true # rmdir only removes empty directories
fi

# -------------------------------
# 7. Optional: delete entire repo
# -------------------------------
printf "Remove entire repo directory? (YES to delete $BASE_DIR): "
read -r remove_repo
if [ "$remove_repo" = "YES" ]; then
  # It's safer to use the absolute path directly than `cd /` then `rm`.
  # This also ensures the script deletes the correct directory even if `cd /` somehow failed.
  rm -rf "$BASE_DIR"
  echo "Deleted $BASE_DIR"
else
  echo "Repo kept at $BASE_DIR"
fi

echo
echo "Cleanup complete."