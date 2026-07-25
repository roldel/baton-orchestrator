#!/bin/sh
set -eu

BASE_DIR="/opt/baton-orchestrator"

# --- Root Check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root." >&2
  exit 1
fi

# --- Dependencies --- 
if command -v apk >/dev/null 2>&1; then
  echo "Installing required packages via apk..."
  apk update >/dev/null
  apk add --no-cache \
  docker \
  docker-cli-compose \
  git \
  gettext \
  openssl \
  inotify-tools \
  busybox \
  busybox-openrc >/dev/null

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

#--- Host filesystem ---
echo "Creating required directories..."
mkdir -p \
  "/srv/projects" \
  "/srv/shared-files" \
  "/srv/baton-orchestrator/webhooks.d" \
  "/srv/webhooks/signals" \
  "/etc/letsencrypt" \
  "/opt/baton-orchestrator/tmp/rendered"


# --- Script permissions ---
# Ensure all shell scripts under scripts/ are executable.
# Covers cmd/, tools/, and top-level scripts so nothing needs a manual
# chmod after a fresh clone or after pulling new scripts from git.
echo "Setting script permissions..."
find "$BASE_DIR/scripts" -type f -name "*.sh" -exec chmod 755 {} +
echo "  Done."


# --- Install baton CLI ---
echo "Installing baton CLI to /usr/local/bin/baton..."
cp "$BASE_DIR/scripts/baton" /usr/local/bin/baton
chmod 755 /usr/local/bin/baton
echo "  Done. You can now run 'baton <command>' from anywhere."


# --- Docker prerequisites ---
echo "Ensuring Docker is enabled and running..."
rc-update add docker default >/dev/null || true
rc-service docker start || true

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


# --- Crond prerequisites ---
echo "Ensuring crond is enabled and running..."
rc-update add crond default >/dev/null || true
rc-service crond start || true


# --- Orchestrator Services: Clean Start ---
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


# --- SSL Renewal Cron Job ---
SOURCE_RENEW="/opt/baton-orchestrator/scripts/tools/ssl/cron-renew-certs.sh"
CRON_FILE="/etc/crontabs/root"
CRON_LINE='0 2,14 * * * /opt/baton-orchestrator/scripts/tools/ssl/cron-renew-certs.sh'

echo "Installing certificate renewal cron job (2:00 and 14:00 daily)..."

# Ensure the script exists and is executable
if [ ! -f "$SOURCE_RENEW" ]; then
  echo "ERROR: Renewal script not found at $SOURCE_RENEW" >&2
  exit 1
fi
chmod 755 "$SOURCE_RENEW"

# Ensure cron file exists
touch "$CRON_FILE"
chmod 600 "$CRON_FILE"

# Add line only if it's not already present (idempotent)
if ! grep -Fq "$CRON_LINE" "$CRON_FILE"; then
  echo "$CRON_LINE" >> "$CRON_FILE"
  echo "  Added cron line to $CRON_FILE"
else
  echo "  Cron line already present in $CRON_FILE (skipping)"
fi



# --- Baton Webhook Service (OpenRC) --- 

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


# --- Completion ---
echo
echo "Setup complete!"
echo "   Nginx is running"
echo "   Webhook service is running"
#echo "   baton-webhook is running (logs: /var/log/baton-webhook.log)"
echo "   Certbot will start on-demand during first deploy"
echo "   Run: ./scripts/cmd/deploy.sh <project-name>"
