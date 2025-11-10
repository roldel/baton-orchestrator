#!/bin/sh
# Irreversible cleanup; run as root
set -eu

# Resolve repo root
if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
  REAL_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
else
  REAL_PATH="$0"
fi
REAL_DIR=$(CDPATH= cd -- "$(dirname -- "$REAL_PATH")" && pwd)
BASE_DIR=$(CDPATH= cd -- "$REAL_DIR/.." && pwd)

echo "Cleaning baton-orchestrator from: $BASE_DIR"
echo "THIS WILL DELETE ALL CONFIGS, CERTS, AND SHARED FILES!"
printf "Type YES to continue: "
read -r confirm
[ "$confirm" != "YES" ] && { echo "Aborted."; exit 1; }

COMPOSE_FILE="$BASE_DIR/orchestrator/docker-compose.yml"

# Stop stack if possible
if [ -f "$COMPOSE_FILE" ] && docker info >/dev/null 2>&1; then
  echo "Stopping orchestrator..."
  docker compose -f "$COMPOSE_FILE" down -v || true
fi

# Remove baton from PATH variants
for p in /usr/local/bin/baton /usr/local/sbin/baton /usr/bin/baton; do
  [ -e "$p" ] && { rm -f "$p"; echo "Removed $p"; }
done
hash -r 2>/dev/null || true

# Remove Docker network
if docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
  echo "Removing network: internal_proxy_pass_network"
  docker network rm internal_proxy_pass_network || true
fi

# Remove repo data dirs
echo "Removing data directories..."
rm -rf "$BASE_DIR/orchestrator/data" \
       "$BASE_DIR/orchestrator/servers-confs" \
       "$BASE_DIR/orchestrator/webhook-redeploy-instruct" 2>/dev/null || true

# Remove shared files
if [ -d /shared-files ]; then
  echo "Removing /shared-files (all static/media)"
  rm -rf /shared-files/*
  rmdir /shared-files 2>/dev/null || true
fi

printf "Remove entire repo directory? (YES to delete $BASE_DIR): "
read -r remove_repo
if [ "$remove_repo" = "YES" ]; then
  cd /
  rm -rf "$BASE_DIR"
  echo "Deleted $BASE_DIR"
else
  echo "Repo kept at $BASE_DIR"
fi

echo
echo "Cleanup complete."
