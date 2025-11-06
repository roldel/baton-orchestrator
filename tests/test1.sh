#!/bin/sh
set -eu

echo "[test_failure_example] Simulating a failed check..."

# This condition is intentionally wrong
if [ $((2 + 2)) -eq 5 ]; then
  echo "[test_failure_example] ❌ Unexpectedly passed"
  exit 0
else
  echo "[test_failure_example] ❗ Expected failure triggered"
  exit 1
fi
