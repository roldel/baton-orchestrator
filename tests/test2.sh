#!/bin/sh
set -eu

echo "[test_sanity_check] Checking that 1 + 1 equals 2..."

if [ $((1 + 1)) -eq 2 ]; then
  echo "[test_sanity_check] ✅ Math checks out"
  exit 0
else
  echo "[test_sanity_check] ❌ Math is broken"
  exit 1
fi
