#!/bin/sh
# Run once as root on Alpine (OpenRC)
set -eu
: "${BASE_DIR:=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
echo "Setting up baton-orchestrator in: $BASE_DIR"

# --- Root Check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root." >&2
  exit 1
fi

#-------------#
# Dependencies
#-------------#
if command -v apk >/dev/null 2>&1; then
  echo "Installing required packages via apk..."
  apk update >/dev/null
  apk add --no-cache \
    docker \
    docker-cli-compose \
    git \
    gettext \
    openssl \
    inotify-tools >/dev/null \
    busybox \
    busybox-openrc
else
  echo "apk not found; skipping package install (this script targets Alpine)."
fi

# --- Sanity Check: Required commands now present after package installation ---
for cmd in docker rc-update rc-service crond; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command '$cmd' not found after package installation. Please check Alpine packages." >&2
    exit 1
  fi
done

#----------------#
# Host filesystem
#----------------#
echo "Creating required directories..."
mkdir -p \
  "$BASE_DIR/orchestrator/data/certs" \
  "$BASE_DIR/orchestrator/data/certbot-webroot" \
  "$BASE_DIR/orchestrator/server-confs" \
  "$BASE_DIR/orchestrator/webhook-redeploy-instruct" \
  /shared-files \
  "$BASE_DIR/logs"

#--------------------#
# Docker prerequisites
#--------------------#
echo "Ensuring Docker is enabled and running..."
rc-update add docker default >/dev/null || true
rc-service docker start || true
if command -v docker >/dev/null 2>&1; then
  # Create network if missing
  if ! docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
    echo "Creating Docker network: internal_proxy_pass_network"
    docker network create internal_proxy_pass_network
  else
    echo "Network already exists: internal_proxy_pass_network"
  fi
  # Optional: verify compose v2
  if ! docker compose version >/dev/null 2>&1; then
    echo "WARNING: 'docker compose' not available. Ensure docker-cli-compose is installed."
  fi
else
  echo "WARNING: Docker not found on PATH. Install/enable Docker before deploying."
fi

#--------------------#
# Crond prerequisites
#--------------------#
echo "Ensuring crond is enabled and running..."
rc-update add crond default >/dev/null || true
rc-service crond start || true

#--------------------#
# Orchestrator Services: Clean Start
#--------------------#
ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"
if [ -f "$ORCHESTRATOR_COMPOSE" ]; then
  echo "Stopping any existing orchestrator services (clean state)..."
  docker compose -f "$ORCHESTRATOR_COMPOSE" down --remove-orphans || true
  echo "Starting nginx and webhook..."
  docker compose -f "$ORCHESTRATOR_COMPOSE" up -d nginx webhook
else
  echo "ERROR: Missing $ORCHESTRATOR_COMPOSE" >&2
  exit 1
fi

#--------------------#
# SSL Renewal Cron Job
#--------------------#
# Using the hardcoded version of the renewal script directly.
CRON_JOB_SRC="$BASE_DIR/scripts/tools/cron-jobs/renew-all-certs-hardcoded.sh"
CRON_WRAPPER_DEST="/etc/periodic/daily/baton-ssl-renewal"
RENEWAL_LOG="$BASE_DIR/logs/cert-renewal.log"
echo "Installing daily SSL renewal job..."
[ -f "$CRON_JOB_SRC" ] || { echo "ERROR: Missing cron job source: $CRON_JOB_SRC" >&2; exit 1; }
cp "$CRON_JOB_SRC" "$CRON_WRAPPER_DEST"
# No sed replacement needed for the hardcoded script
chmod 755 "$CRON_WRAPPER_DEST"
echo "  Installed: $CRON_WRAPPER_DEST (runs with system's daily periodic cron)"
echo "  Logs:      $RENEWAL_LOG"

#--------------------#
# Baton Webhook Service (OpenRC)
#--------------------#
BATON_WEBHOOK_SERVICE_FILE="$BASE_DIR/scripts/tools/webhook/service-file.sh"
INIT_D_SERVICE_FILE="/etc/init.d/baton-webhook"
BATON_WEBHOOK_LOG_FILE="/var/log/baton-webhook.log"
echo "Setting up baton-webhook service..."
if rc-service baton-webhook status >/dev/null 2>&1; then
  echo "  Stopping existing baton-webhook service..."
  rc-service baton-webhook stop || true
fi
if rc-update show | grep -q "baton-webhook"; then
  echo "  Removing existing baton-webhook from runlevels..."
  rc-update del "baton-webhook" "default" || true
fi
cp -f "$BATON_WEBHOOK_SERVICE_FILE" "$INIT_D_SERVICE_FILE"
chmod +x "$INIT_D_SERVICE_FILE"
rc-update add "baton-webhook" "default"
touch "$BATON_WEBHOOK_LOG_FILE"
chmod 644 "$BATON_WEBHOOK_LOG_FILE"
rc-service baton-webhook start

#--------------------#
# Completion
#--------------------#
echo
echo "Setup complete!"
echo "   Nginx is running"
echo "   Webhook service is running"
echo "   baton-webhook is running (logs: /var/log/baton-webhook.log)"
echo "   Certbot will start on-demand during first deploy"
echo "   Run: ./scripts/cmd/deploy.sh <project-name>"
