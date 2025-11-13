#!/bin/sh
# Test nginx configuration inside the ingress-nginx container
# Uses docker compose to exec `nginx -t` in the "nginx" service.

set -eu

BASE_DIR="/opt/baton-orchestrator"
ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"
NGINX_SERVICE_NAME="nginx"          # service name in docker-compose.yml
NGINX_CONTAINER_NAME="ingress-nginx" # container_name in docker-compose.yml (for logging only)

echo "[nginx-test] Testing Nginx configuration via service '$NGINX_SERVICE_NAME' (container: $NGINX_CONTAINER_NAME)"

# --- Basic validation ---
if [ ! -f "$ORCHESTRATOR_COMPOSE" ]; then
  echo "[nginx-test] ERROR: Orchestrator compose file not found: $ORCHESTRATOR_COMPOSE" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[nginx-test] ERROR: docker command not found." >&2
  exit 1
fi

# Optional: check that the nginx service is up (not strictly required, but helpful)
if ! docker compose -f "$ORCHESTRATOR_COMPOSE" ps "$NGINX_SERVICE_NAME" >/dev/null 2>&1; then
  echo "[nginx-test] WARNING: Nginx service '$NGINX_SERVICE_NAME' not listed by docker compose ps." >&2
  echo "[nginx-test] Proceeding to exec nginx -t anyway..." >&2
fi

# --- Run nginx -t ---
echo "[nginx-test] Running: docker compose -f $ORCHESTRATOR_COMPOSE exec $NGINX_SERVICE_NAME nginx -t"

# We do not use -T so output stays attached and visible
if docker compose -f "$ORCHESTRATOR_COMPOSE" exec "$NGINX_SERVICE_NAME" nginx -t; then
  echo "[nginx-test] Nginx configuration is VALID."
else
  echo "[nginx-test] ERROR: Nginx configuration test FAILED." >&2
  exit 1
fi
