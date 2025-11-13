#!/bin/sh
set -eu

# --- Usage check ---
if [ $# -lt 2 ]; then
  echo "Usage: $0 <project-name> <VAR1> [VAR2 VAR3 ...]" >&2
  exit 1
fi

PROJECT="$1"
shift 1   # Remaining args are the list of variables to validate

PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"

echo "[validate-env] Validating env file: $ENV_FILE"

if [ ! -f "$ENV_FILE" ]; then
  echo "[deploy:20] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

# Load env vars
# shellcheck source=/dev/null
. "$ENV_FILE"

REQUIRED_VARS="$@"
MISSING=0

echo "[validate-env] Checking vars: $REQUIRED_VARS"

for v in $REQUIRED_VARS; do
  eval "val=\${$v:-}"
  if [ -z "$val" ]; then
    echo "[validate-env] ERROR: Missing required env var: $v" >&2
    MISSING=1
  fi
done

if [ "$MISSING" -ne 0 ]; then
  echo "[validate-env] One or more required env vars are missing. Aborting." >&2
  exit 1
fi

echo "[validate-env] Env validation OK."
