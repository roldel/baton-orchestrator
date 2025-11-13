#!/bin/sh
# scripts/tools/projects/check-site-live.sh
# One-liner tool: verifies a project is fully live (SSL + nginx config)
# Usage: check-site-live.sh <project-name>

set -eu

PROJECT="${1:-}"
[ -z "$PROJECT" ] && echo "Usage: $0 <project-name>" >&2 && exit 1

PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"
BASE_DIR="/opt/baton-orchestrator"

# Load DOMAIN_NAME
[ -f "$ENV_FILE" ] || { echo "Missing .env in $PROJECT_DIR" >&2; exit 1; }
# shellcheck source=/dev/null
. "$ENV_FILE"
[ -z "${DOMAIN_NAME:-}" ] && { echo "DOMAIN_NAME not set in $ENV_FILE" >&2; exit 1; }

# Paths to check
CERT="/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
CONF="$BASE_DIR/orchestrator/nginx/conf.d/${DOMAIN_NAME}.conf"

# Do the checks
[ -f "$CERT" ] || { echo "SSL cert missing: $CERT" >&2; exit 1; }
[ -f "$CONF" ]  || { echo "Nginx config missing: $CONF" >&2; exit 1; }

echo "$PROJECT is LIVE ($DOMAIN_NAME)"
exit 0