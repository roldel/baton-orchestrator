#!/bin/sh
set -eu

echo "[test_env_setup_success] Testing env-setup.sh with valid structure..."

# Resolve project root (2 levels up from tests/unit)
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"

FAKE_BASE=$(mktemp -d)
trap 'rm -rf "$FAKE_BASE"' EXIT

mkdir -p "$FAKE_BASE/orchestrator" "$FAKE_BASE/projects"

if BASE_DIR="$FAKE_BASE" sh "$PROJECT_ROOT/env-setup.sh" > /dev/null 2>&1; then
  echo "[test_env_setup_success] ✅ env-setup.sh succeeded as expected"
  exit 0
else
  echo "[test_env_setup_success] ❌ env-setup.sh failed unexpectedly"
  exit 1
fi
