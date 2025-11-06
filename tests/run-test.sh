#!/bin/sh
set -eu

: "${TEST_DIR:=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
echo "🔍 Running all test scripts in $TEST_DIR (recursively)"

TOTAL=0
PASSED=0
FAILED=0
RUNNER="$(realpath "$0")"

TEST_SCRIPTS=$(find "$TEST_DIR" -type f -name "*.sh" | sort)

for test_script in $TEST_SCRIPTS; do
  # Skip the runner itself
  if [ "$(realpath "$test_script")" = "$RUNNER" ]; then
    continue
  fi

  TOTAL=$((TOTAL + 1))
  echo "▶️  Running: $test_script"
  if sh "$test_script"; then
    echo "✅ $test_script PASSED"
    PASSED=$((PASSED + 1))
  else
    echo "❌ $test_script FAILED"
    FAILED=$((FAILED + 1))
  fi
  echo ""
done

echo "📊 Total tests run: $TOTAL"
echo "✅ Passed: $PASSED"
echo "❌ Failed: $FAILED"

if [ "$FAILED" -eq 0 ]; then
  echo "🎉 All tests passed!"
else
  echo "❗ Some tests failed."
  exit 1
fi
