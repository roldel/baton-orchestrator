#!/bin/sh
set -eu

LOGFILE="/var/log/baton-cert-renew.log"
mkdir -p /var/log

# Ensure the log file is created and writable before redirecting
touch "$LOGFILE" || { echo "ERROR: Could not create log file: $LOGFILE" >&2; exit 1; }
chmod 644 "$LOGFILE" # Ensure proper permissions

# Execute the rest of the script within a subshell with stdout/stderr redirected
(
  echo "----- $(date '+%Y-%m-%d %H:%M:%S') Starting renewal -----"

  BASE_DIR="/opt/baton-orchestrator"
  ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"

  echo "[renew] Running certbot renew..."
  OUTPUT="$(docker compose -f "$ORCHESTRATOR_COMPOSE" run --rm certbot renew 2>&1 || true)"

  echo "$OUTPUT"

  if echo "$OUTPUT" | grep -q "Renewing an existing certificate"; then
      echo "[renew] Certificates renewed → reloading nginx..."
      sh "$BASE_DIR/scripts/tools/nginx/reload.sh"
  else
      echo "[renew] No renewal needed."
  fi

  echo "----- $(date '+%Y-%m-%d %H:%M:%S') Done -----"
) >> "$LOGFILE" 2>&1