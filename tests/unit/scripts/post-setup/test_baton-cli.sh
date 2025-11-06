#!/bin/sh
set -eu

echo "[post_baton_cli] Verifying 'baton' on PATH and runnable..."

if ! command -v baton >/dev/null 2>&1; then
  echo "❌ 'baton' not found on PATH"
  exit 1
fi

BATON_BIN="$(command -v baton)"
if [ ! -x "$BATON_BIN" ]; then
  echo "❌ 'baton' is not executable: $BATON_BIN"
  exit 1
fi

if baton --help >/dev/null 2>&1; then
  echo "✅ 'baton' available and responds: $BATON_BIN"
  exit 0
else
  echo "❌ 'baton --help' failed to run"
  exit 1
fi
