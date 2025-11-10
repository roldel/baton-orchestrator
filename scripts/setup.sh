#!/bin/sh
# Run once as root on Alpine (OpenRC)
set -eu

: "${BASE_DIR:=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"

echo "Setting up baton-orchestrator in: $BASE_DIR"

#-------------#
# Log directory
#-------------#
mkdir -p "$BASE_DIR/logs"

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
# Webhook inotify watcher
#--------------------#
echo "[setup] Setting up webhook inotify watcher..."

# Ensure inotify-tools is installed (already done above, but double-check)
if ! command -v inotifywait >/dev/null 2>&1; then
    echo "ERROR: inotifywait not found. Ensure inotify-tools is installed." >&2
    exit 1
fi

# Create signal directory
SIGNAL_DIR="$BASE_DIR/orchestrator/webhook-redeploy-instruct"
mkdir -p "$SIGNAL_DIR"

# Define paths
INOTIFY_SCRIPT="$BASE_DIR/scripts/tools/webhook/inotify-setup.sh"
PID_FILE="$BASE_DIR/.webhook-watcher.pid"

# Validate script
[ -x "$INOTIFY_SCRIPT" ] || { echo "ERROR: $INOTIFY_SCRIPT not executable" >&2; exit 1; }

# Kill any old watcher
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[setup] Stopping old watcher (PID: $OLD_PID)"
        kill "$OLD_PID" || true
    fi
    rm -f "$PID_FILE"
fi

# Start new watcher
echo "[setup] Starting inotify watcher → $INOTIFY_SCRIPT"
nohup "$INOTIFY_SCRIPT" > "$BASE_DIR/logs/webhook-watcher.log" 2>&1 &
WATCHER_PID=$!
echo "$WATCHER_PID" > "$PID_FILE"

# Verify
sleep 1
if kill -0 "$WATCHER_PID" 2>/dev/null; then
    echo "[setup] Webhook watcher started (PID: $WATCHER_PID)"
    echo "    → Log: $BASE_DIR/logs/webhook-watcher.log"
else
    echo "ERROR: Webhook watcher failed to start" >&2
    rm -f "$PID_FILE"
    exit 1
fi

#--------------------#
# Completion
#--------------------#
echo
echo "Setup complete!"
echo "   Nginx is running"
echo "   Webhook service is running"
echo "   Webhook watcher is running (logs: $BASE_DIR/logs/webhook-watcher.log)"
echo "   Certbot will start on-demand during first deploy"
echo "   Run: ./scripts/cmd/deploy.sh <project-name>"