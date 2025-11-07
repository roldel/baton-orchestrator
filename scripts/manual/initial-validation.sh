#!/bin/sh
# Usage: ./scripts/manual/initial-validation.sh <project-name>

# Fail on unset vars; we’ll handle errors explicitly with messages.
set -u

echo "[initial-validation] Starting…"

# Arg check
if [ "${#}" -lt 1 ]; then
  echo "ERROR: Missing project name." >&2
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"
PROJECT_DIR="projects/$PROJECT"

echo "[initial-validation] Project name: $PROJECT"
echo "[initial-validation] Expecting directory: $PROJECT_DIR"

# Check project directory exists
if [ -d "$PROJECT_DIR" ]; then
  echo "[initial-validation] ✅ Found project directory."
else
  echo "ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

# Check required files
MISSING=0

echo "[initial-validation] Checking required files: .env, server.conf"

if [ -f "$PROJECT_DIR/.env" ]; then
  if [ -r "$PROJECT_DIR/.env" ]; then
    echo "[initial-validation] ✅ .env present and readable."
  else
    echo "ERROR: .env exists but is not readable: $PROJECT_DIR/.env" >&2
    MISSING=1
  fi
else
  echo "ERROR: Missing .env at $PROJECT_DIR/.env" >&2
  MISSING=1
fi

if [ -f "$PROJECT_DIR/server.conf" ]; then
  if [ -r "$PROJECT_DIR/server.conf" ]; then
    echo "[initial-validation] ✅ server.conf present and readable."
  else
    echo "ERROR: server.conf exists but is not readable: $PROJECT_DIR/server.conf" >&2
    MISSING=1
  fi
else
  echo "ERROR: Missing server.conf at $PROJECT_DIR/server.conf" >&2
  MISSING=1
fi

# Final result
if [ "$MISSING" -ne 0 ]; then
  echo "[initial-validation] ❌ Validation failed."
  exit 1
fi

echo "[initial-validation] 🎉 Validation OK."
exit 0
