#!/bin/sh
# Run once as root on Alpine (OpenRC)
set -eu
: "${BASE_DIR:=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
echo "Setting up baton-orchestrator in: $BASE_DIR"

#-------------#
# Log directory
#-------------#
mkdir -p "$BASE_DIR/logs"
# Ensure cron.d exists on minimal images
mkdir -p /etc/cron.d

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
    inotify-tools >/dev/null
  # Enable & start Docker (OpenRC)
  rc-update add docker default >/dev/null || true
  rc-service docker start || true
else
  echo "apk not found; skipping package install (this script targets Alpine)."
fi

#----------------#
# Host filesystem
#----------------#
mkdir -p \
  "$BASE_DIR/orchestrator/data/certs" \
  "$BASE_DIR/orchestrator/data/certbot-webroot" \
  "$BASE_DIR/orchestrator/server-confs" \
  "$BASE_DIR/orchestrator/webhook-redeploy-instruct" \
  /shared-files

#--------------------#
# Docker prerequisites
#--------------------#
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
CRON_JOB_FILE="/etc/cron.d/baton-ssl-renewal"
RENEWAL_SCRIPT="$BASE_DIR/scripts/cmd/renew-all-certs.sh"
RENEWAL_LOG="$BASE_DIR/logs/cert-renewal.log"

echo "Setting up SSL certificate renewal cron job..."

# Ensure renewal script is executable
chmod +x "$RENEWAL_SCRIPT"
# Ensure the renewal log file path exists (script may append to it)
touch "$RENEWAL_LOG"

# Create the cron job file
cat <<EOF > "$CRON_JOB_FILE"
# Cron job for Baton Orchestrator SSL certificate renewal
# Runs daily at 2:30 AM.
# M H DOM MON DOW user command
30 2 * * * root "$RENEWAL_SCRIPT"
EOF

chmod 644 "$CRON_JOB_FILE" # Cron files usually need 0644

echo "  SSL renewal cron job created at $CRON_JOB_FILE. It will run daily."
echo "  Logs will be available at $RENEWAL_LOG"

# On Alpine, cron is often vCrony or busybox cron, which usually picks up changes to /etc/cron.d
# For more robustness, you might restart cron service if available, e.g., rc-service crond restart

#--------------------#
# Baton Webhook Service (OpenRC)
#--------------------#
BATON_WEBHOOK_SERVICE_FILE="$BASE_DIR/scripts/tools/webhook/service-file.sh"
INIT_D_SERVICE_FILE="/etc/init.d/baton-webhook"
BATON_WEBHOOK_LOG_FILE="/var/log/baton-webhook.log"

echo "Setting up baton-webhook service..."

# Stop and disable existing service if it exists for a clean setup
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
