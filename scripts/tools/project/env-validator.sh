#!/bin/sh
# Validate required env vars for a project (.env in projects/<name>)
# Usage: env-validator.sh <project-name>
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
PROJ_DIR="$ROOT/projects/$PROJECT"
ENV_FILE="$PROJ_DIR/.env"

[ -r "$ENV_FILE" ] || { echo "ERROR: Missing or unreadable $ENV_FILE" >&2; exit 1; }

# Load env
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

FAILED=0

# --- Required: DOMAIN_NAME ---
if [ -z "${DOMAIN_NAME:-}" ]; then
  echo "ERROR: DOMAIN_NAME is required in $ENV_FILE" >&2
  FAILED=1
fi

# --- Required: DOMAIN_ADMIN_EMAIL ---
if [ -z "${DOMAIN_ADMIN_EMAIL:-}" ]; then
  echo "ERROR: DOMAIN_ADMIN_EMAIL is required in $ENV_FILE" >&2
  FAILED=1
else
  # Basic sanity check for email format (portable enough for BusyBox grep -E)
  if ! printf '%s' "$DOMAIN_ADMIN_EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; then
    echo "ERROR: DOMAIN_ADMIN_EMAIL looks invalid: '$DOMAIN_ADMIN_EMAIL'" >&2
    FAILED=1
  fi
fi

# --- Optional: DOMAIN_ALIASES (comma or space separated) ---
# Normalize now (just to surface obvious whitespace-only cases)
if [ -n "${DOMAIN_ALIASES:-}" ]; then
  NORMALIZED="$(echo "$DOMAIN_ALIASES" | tr ',' ' ' | xargs || true)"
  if [ -z "$NORMALIZED" ]; then
    echo "WARNING: DOMAIN_ALIASES provided but empty after normalization; ignoring."
  fi
fi

if [ "$FAILED" -ne 0 ]; then
  echo "[env-validator] ❌ Environment validation failed"
  exit 1
fi

echo "[env-validator] ✅ Environment variables OK"
