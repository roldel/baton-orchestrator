#!/bin/sh
# scripts/cmd/renew-all-certs.sh
# Attempts to renew SSL certificates for all deployed projects.
# Reloads Nginx only if a renewal actually occurred.
set -eu

# Resolve BASE_DIR then load shared env
if [ -z "${BASE_DIR:-}" ]; then
  THIS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
  BASE_DIR="$(CDPATH= cd -- "$THIS_DIR/../.." && pwd)"
  export BASE_DIR
fi
# shellcheck disable=SC1091
. "$BASE_DIR/env-setup.sh"

# Redirect all output for this script to the log file, with timestamps
exec > >(tee -a "$LOG_FILE" | sed 's/^/['"$(date '+%Y-%m-%d %H:%M:%S')"'] /') 2>&1

echo "--- Starting SSL Certificate Renewal Check (All Projects) ---"

# Flag to track if any Nginx reload is needed
RELOAD_NGINX=0

# Iterate over all project directories
for PROJECT_DIR in "$PROJECTS_DIR"/*/; do
  PROJECT_NAME="$(basename "$PROJECT_DIR")"
  echo "Processing project: $PROJECT_NAME"

  # Check if project has an .env file
  ENV_FILE="$PROJECT_DIR/.env"
  if [ ! -f "$ENV_FILE" ]; then
    echo "  Skipping $PROJECT_NAME: No .env file found."
    continue
  fi

  # Load project's .env to check DOCKER_COMPOSE and other flags if necessary
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a

  # Check if SSL management is explicitly disabled for this project
  if [ "${DISABLE_SSL_MANAGEMENT:-NO}" = "YES" ]; then
    echo "  Skipping $PROJECT_NAME: SSL management explicitly disabled (DISABLE_SSL_MANAGEMENT=YES in .env)."
    continue
  fi

  # Call ssl-certs-checker.sh: exits 0 if valid, 1 if invalid/needs renewal
  if ! "$SCRIPT_DIR/tools/ssl-management/ssl-certs-checker.sh" "$PROJECT_NAME"; then
    echo "  Certificate for $PROJECT_NAME needs renewal or is invalid. Attempting to issue/renew..."
    if "$SCRIPT_DIR/tools/ssl-management/initial-issual.sh" "$PROJECT_NAME"; then
      echo "  Successfully renewed/issued certificate for $PROJECT_NAME."
      RELOAD_NGINX=1
    else
      echo "  ERROR: Failed to renew/issue certificate for $PROJECT_NAME."
      # Continue to next project even if one fails
    fi
  else
    echo "  Certificate for $PROJECT_NAME is valid and does not require renewal."
  fi
  echo "" # Newline for readability between projects
done

# Reload Nginx if any certificates were renewed
if [ "$RELOAD_NGINX" -eq 1 ]; then
  echo "One or more certificates were renewed. Reloading Nginx..."
  "$SCRIPT_DIR/tools/nginx/server-reload.sh"
  echo "Nginx reloaded successfully."
else
  echo "No certificates required renewal. Nginx reload skipped."
fi

echo "--- SSL Certificate Renewal Check Complete ---"
exit 0