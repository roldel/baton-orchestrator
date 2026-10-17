#!/bin/sh
# Dash test runner. No Docker, nginx, or root. Each phase file is sourced
# with ROOT set and fail() available.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FAILS=0

fail() {
  echo "FAIL: $*" >&2
  FAILS=$((FAILS + 1))
  exit 1
}

ok() {
  echo "ok: $*"
}

# Phase scripts call fail() and ok(). They must not assume a clean environment
# beyond ROOT, so each one isolates its own temp dir.
. "$ROOT/tests/phase1.sh"
. "$ROOT/tests/phase2.sh"
. "$ROOT/tests/phase3.sh"
. "$ROOT/tests/phase4.sh"
. "$ROOT/tests/phase5.sh"
. "$ROOT/tests/phase6.sh"
. "$ROOT/tests/phase7.sh"
. "$ROOT/tests/phase8.sh"
. "$ROOT/tests/phase9.sh"

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS test(s) failed" >&2
  exit 1
fi

echo "all tests passed"
