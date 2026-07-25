#!/bin/sh
# Reload nginx configuration inside the ingress-nginx container
# Assumes `nginx -t` has already been run successfully.

set -eu

BASE_DIR="/opt/baton-orchestrator"
ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"
NGINX_SERVICE_NAME="nginx"           
NGINX_CONTAINER_NAME="ingress-nginx"

echo "[nginx-reload] Reloading Nginx via service '$NGINX_SERVICE_NAME' (container: $NGINX_CONTAINER_NAME)"

# --- Basic validation ---
if [ ! -f "$ORCHESTRATOR_COMPOSE" ]; then
  echo "[nginx-reload] ERROR: Orchestrator compose file not found: $ORCHESTRATOR_COMPOSE" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[nginx-reload] ERROR: docker command not found." >&2
  exit 1
fi

# Optional: check service is known to compose
if ! docker compose -f "$ORCHESTRATOR_COMPOSE" ps "$NGINX_SERVICE_NAME" >/dev/null 2>&1; then
  echo "[nginx-reload] WARNING: Nginx service '$NGINX_SERVICE_NAME' not listed by docker compose ps." >&2
  echo "[nginx-reload] Proceeding to send reload signal anyway..." >&2
fi

# --- Reload nginx ---
echo "[nginx-reload] Running: docker compose -f $ORCHESTRATOR_COMPOSE exec $NGINX_SERVICE_NAME nginx -s reload"

if docker compose -f "$ORCHESTRATOR_COMPOSE" exec "$NGINX_SERVICE_NAME" nginx -s reload; then
  echo "[nginx-reload] Nginx reload OK."
else
  echo "[nginx-reload] ERROR: Nginx reload FAILED." >&2
  exit 1
fi
