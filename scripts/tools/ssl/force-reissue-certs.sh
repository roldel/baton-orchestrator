#!/bin/sh
# Force (re)issue of Let's Encrypt certificates for all domains of a project.
# Strategy:
#   1. Use certbot (via docker compose) to delete the existing cert lineage
#      for DOMAIN_NAME, if it exists.
#   2. Call ensure-certs.sh again, which will re-read .env (DOMAIN_NAME,
#      DOMAIN_ALIASES, DOMAIN_ADMIN_EMAIL) and issue a fresh cert.

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"
ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"
ENSURE_CERTS="$BASE_DIR/scripts/tools/ssl/ensure-certs.sh"

echo "[force-reissue-certs] Forcing certificate re-issue for project: $PROJECT"
echo "[force-reissue-certs] Project dir: $PROJECT_DIR"

# --- Basic validation ---
if [ ! -d "$PROJECT_DIR" ]; then
  echo "[force-reissue-certs] ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "[force-reissue-certs] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

if [ ! -f "$ORCHESTRATOR_COMPOSE" ]; then
  echo "[force-reissue-certs] ERROR: Orchestrator compose file not found: $ORCHESTRATOR_COMPOSE" >&2
  exit 1
fi

if [ ! -x "$ENSURE_CERTS" ]; then
  echo "[force-reissue-certs] ERROR: ensure-certs script not found or not executable: $ENSURE_CERTS" >&2
  exit 1
fi

# --- Load env vars ---
# shellcheck source=/dev/null
. "$ENV_FILE"

if [ -z "${DOMAIN_NAME:-}" ]; then
  echo "[force-reissue-certs] ERROR: DOMAIN_NAME must be set in .env" >&2
  exit 1
fi

echo "[force-reissue-certs] DOMAIN_NAME = $DOMAIN_NAME"

CERT_DIR="/etc/letsencrypt/live/$DOMAIN_NAME"

# --- If a lineage exists, delete it cleanly via certbot ---
if [ -d "$CERT_DIR" ]; then
  echo "[force-reissue-certs] Found existing certificate lineage at $CERT_DIR"
  echo "[force-reissue-certs] Deleting lineage via certbot (docker compose)..."

  # This removes live/, archive/, and renewal/ entries for this cert-name
  docker compose -f "$ORCHESTRATOR_COMPOSE" run --rm certbot delete \
    --cert-name "$DOMAIN_NAME" \
    --non-interactive || {
      echo "[force-reissue-certs] WARNING: certbot delete failed (see logs above)."
      echo "[force-reissue-certs] You may need to inspect /etc/letsencrypt manually."
    }

else
  echo "[force-reissue-certs] No existing lineage for $DOMAIN_NAME under $CERT_DIR; nothing to delete."
fi

# --- Re-run ensure-certs for this project ---
echo "[force-reissue-certs] Re-running ensure-certs for project: $PROJECT"
"$ENSURE_CERTS" "$PROJECT"

echo "[force-reissue-certs] Done."
