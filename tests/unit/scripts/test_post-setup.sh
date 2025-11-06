#!/bin/sh
# tests/unit/test_post_setup.sh
# Self-contained post-setup sanity check (read-only).

set -eu

echo "[test_post_setup] Verifying system state after setup..."

failures=0
ok()  { echo "✅ $*"; }
bad() { echo "❌ $*"; failures=$((failures+1)); }
warn(){ echo "⚠️  $*"; }

# Resolve project root (this file lives in tests/unit/)
: "${BASE_DIR:=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
: "${EXPECTED_BASE:=/opt/baton-orchestrator}"

echo "[test_post_setup] Using BASE_DIR: $BASE_DIR"

# 1) Install location policy (warn-only; flip to 'bad' if you want strict)
if [ "$BASE_DIR" = "$EXPECTED_BASE" ]; then
  ok "Project installed under expected base: $BASE_DIR"
else
  warn "Non-standard install path: $BASE_DIR (expected $EXPECTED_BASE)"
fi

# 2) Baton availability (on PATH and runnable)
if command -v baton >/dev/null 2>&1; then
  BATON_BIN=$(command -v baton)
  [ -x "$BATON_BIN" ] || bad "'baton' found but not executable: $BATON_BIN"
  if baton --help >/dev/null 2>&1; then
    ok "'baton' available and responds"
  else
    bad "'baton --help' failed to run"
  fi
else
  bad "'baton' not found on PATH"
fi

# 3) Minimal canary directories created by setup
CANARIES="
$BASE_DIR/orchestrator/servers-confs
$BASE_DIR/orchestrator/data/certs
"
for d in $CANARIES; do
  if [ -d "$d" ]; then
    ok "Directory exists: $d"
  else
    bad "Missing directory: $d"
  fi
done

# 4) Optional: shared system dir (warn-only)
if [ -d /shared-files ]; then
  ok "Directory exists: /shared-files"
else
  warn "Missing /shared-files (expected after setup)"
fi

# Summary
if [ "$failures" -eq 0 ]; then
  echo "[test_post_setup] ✅ All checks passed"
  exit 0
else
  echo "[test_post_setup] ❗ $failures issue(s) detected"
  exit 1
fi
