#!/bin/sh
# tests/unit/test_post-setup.sh
# Self-contained post-setup sanity check.
# Ensures baton binary exists, key directories are present, and install path looks correct.

set -eu

echo "[test_post_setup] Verifying system state after setup..."

failures=0
ok()  { echo "✅ $*"; }
bad() { echo "❌ $*"; failures=$((failures+1)); }
warn(){ echo "⚠️  $*"; }

# Derive project base (assumed this test lives under /tests/unit/)
BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# --- 1. Install location check ---
EXPECTED_BASE="/opt/baton-orchestrator"
if [ "$BASE_DIR" = "$EXPECTED_BASE" ]; then
  ok "Project installed under expected base: $BASE_DIR"
else
  warn "Non-standard install path: $BASE_DIR (expected $EXPECTED_BASE)"
fi

# --- 2. Baton binary availability ---
if command -v baton >/dev/null 2>&1; then
  BATON_BIN=$(command -v baton)
  if [ -x "$BATON_BIN" ]; then
    ok "'baton' found and executable at: $BATON_BIN"
  else
    bad "'baton' found but not executable: $BATON_BIN"
  fi
else
  bad "'baton' command not found on PATH"
fi

# --- 3. Key directories existence ---
dirs="
$BASE_DIR/orchestrator/servers-confs
$BASE_DIR/orchestrator/data/certs
/shared-files
"
for d in $dirs; do
  if [ -d "$d" ]; then
    ok "Directory exists: $d"
  else
    bad "Missing directory: $d"
  fi
done

# --- 4. Optional docker availability ---
if command -v docker >/dev/null 2>&1; then
  ok "Docker available on system"
else
  warn "Docker not found on PATH (expected on Alpine host)"
fi

# --- 5. Summary and exit ---
if [ "$failures" -eq 0 ]; then
  echo "[test_post_setup] ✅ All checks passed"
  exit 0
else
  echo "[test_post_setup] ❗ $failures issue(s) detected"
  exit 1
fi
