#!/bin/sh
set -eu

echo "[post_docker_presence] Checking Docker presence (warn-only)..."

if command -v docker >/dev/null 2>&1; then
  echo "✅ Docker available"
  # Optionally check network presence but don’t mutate:
  if docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
    echo "✅ Network exists: internal_proxy_pass_network"
  else
    echo "⚠️  Network missing: internal_proxy_pass_network"
  fi
  exit 0
else
  echo "⚠️  Docker not found on PATH"
  exit 0
fi
