#!/bin/sh
# Cleanup / uninstall Baton Orchestrator runtime
# - Does NOT touch /srv/projects
# - Does NOT wipe /etc/letsencrypt
# - Does NOT remove docker/crond from runlevels (you can do that manually if desired)

set -eu

BASE_DIR="/opt/baton-orchestrator"
ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"

INIT_D_SERVICE_FILE="/etc/init.d/baton-webhook"
WEBHOOK_LOG="/var/log/baton-webhook.log"
WEBHOOK_PID="/run/baton-webhook.pid"

echo "[cleanup] Baton Orchestrator cleanup starting..."

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root." >&2
  exit 1
fi

# --- Stop docker stack (nginx + webhook + certbot) ---
if command -v docker >/dev/null 2>&1 && [ -f "$ORCHESTRATOR_COMPOSE" ]; then
  echo "[cleanup] Stopping orchestrator docker-compose stack..."
  docker compose -f "$ORCHESTRATOR_COMPOSE" down --remove-orphans --volumes || true
else
  echo "[cleanup] Skipping docker-compose stack teardown (docker or compose file missing)."
fi

# --- Remove the dedicated docker network if possible ---
if command -v docker >/dev/null 2>&1; then
  if docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
    echo "[cleanup] Attempting to remove docker network: internal_proxy_pass_network"
    if ! docker network rm internal_proxy_pass_network >/dev/null 2>&1; then
      echo "[cleanup]   Could not remove internal_proxy_pass_network (likely still in use). Skipping."
    fi
  fi
fi

# --- OpenRC baton-webhook service cleanup ---
if command -v rc-service >/dev/null 2>&1; then
  if rc-service baton-webhook status >/dev/null 2>&1; then
    echo "[cleanup] Stopping baton-webhook service..."
    rc-service baton-webhook stop || true
  fi
fi

if command -v rc-update >/dev/null 2>&1; then
  if rc-update show | grep -q "baton-webhook"; then
    echo "[cleanup] Removing baton-webhook from default runlevel..."
    rc-update del baton-webhook default || true
  fi
fi

if [ -f "$INIT_D_SERVICE_FILE" ]; then
  echo "[cleanup] Removing OpenRC service file: $INIT_D_SERVICE_FILE"
  rm -f "$INIT_D_SERVICE_FILE"
fi

# --- Cron job cleanup ---
TARGET_RENEW="/etc/periodic/daily/baton-cert-renew"

if [ -f "$TARGET_RENEW" ]; then
    echo "[cleanup] Removing cert renewal periodic script..."
    rm -f "$TARGET_RENEW"
fi


# --- Remove log / pid ---
[ -f "$WEBHOOK_LOG" ] && rm -f "$WEBHOOK_LOG" || true
[ -f "$WEBHOOK_PID" ] && rm -f "$WEBHOOK_PID" || true

# --- Remove orchestrator runtime directories (safe ones only) ---
echo "[cleanup] Removing orchestrator runtime directories..."

# Temporary + generated nginx configs
rm -rf \
  "$BASE_DIR/tmp" \
  "$BASE_DIR/orchestrator/nginx/conf.d" 2>/dev/null || true

# Webhook helper dirs used by the watcher / service
rm -rf \
  /opt/baton-orchestrator/webhook-redeploy-instruct 2>/dev/null || true

# Old/alternate webhook host dirs (these do not overlap /srv/projects)
rm -rf \
  /srv/baton-orchestrator \
  /srv/webhooks/signals \
  /srv/webhooks/projects 2>/dev/null || true

# --- Remove leftover backup dirs created by handle-webhook.sh ---
if [ -d /srv/tmp ]; then
  echo "[cleanup] Removing baton backup directories in /srv/tmp..."
  # ignore errors if none exist
  find /srv/tmp -maxdepth 1 -type d -name "baton-backup.*" -exec rm -rf {} + 2>/dev/null || true
fi

echo
echo "[cleanup] Baton Orchestrator cleanup completed."
echo "[cleanup] NOTE: /srv/projects was NOT modified."
echo "[cleanup] NOTE: /srv/shared-files and /etc/letsencrypt were NOT touched."
echo "[cleanup] If you also want to remove /opt/baton-orchestrator entirely, you can do so manually:"
echo "         rm -rf /opt/baton-orchestrator"
