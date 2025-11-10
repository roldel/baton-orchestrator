#!/bin/sh
# Validate cert existence, SAN coverage, and minimum validity (>= 3 days)
# Exit 0 → valid; Exit 1 → invalid
# Usage: ssl-certs-checker.sh <project-name>
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/env-setup.sh"

ENV_FILE="$PROJECTS_DIR/$PROJECT/.env"
[ -r "$ENV_FILE" ] || { echo "ERROR: Cannot read $ENV_FILE" >&2; exit 1; }

# Load env
echo "[certs] Debug: Loading .env from $ENV_FILE"
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

[ -n "${DOMAIN_NAME:-}" ] || { echo "ERROR: DOMAIN_NAME missing in $ENV_FILE" >&2; exit 1; }
ALIASES_RAW="${DOMAIN_ALIASES:-}"
# normalize: spaces
ALIASES="$(echo "$ALIASES_RAW" | tr ',' ' ' | xargs || true)"

LIVE_DIR="$CERTS_DIR/live/$DOMAIN_NAME"
FULLCHAIN="$LIVE_DIR/fullchain.pem"

echo "[certs] Debug: FULLCHAIN is $FULLCHAIN"

min_days_left=3

if [ ! -f "$FULLCHAIN" ]; then
  echo "[certs] No certificate found at $FULLCHAIN"
  exit 1
fi
echo "[certs] Debug: Certificate file found."

# Check expiry days left
enddate="$(openssl x509 -enddate -noout -in "$FULLCHAIN" | cut -d= -f2)"

# --- NEW DATE PARSING LOGIC FOR BUSYBOX/ALPINE ---
# Goal: Transform "Feb  8 04:49:23 2026 GMT" into something BusyBox `date` can reliably parse,
# e.g., "Feb 8 04:49:23 2026" or a "YYYY-MM-DD HH:MM:SS" format.
# We'll remove the timezone and normalize spacing.
normalized_enddate="$(echo "$enddate" | sed -E 's/ +/ /g' | sed 's/ GMT//' | xargs)"

echo "[certs] Debug: openssl raw enddate: '$enddate'"
echo "[certs] Debug: normalized enddate for parsing: '$normalized_enddate'"

# Attempt to parse the normalized date string
end_epoch="$(date -d "$normalized_enddate" +%s 2>/dev/null || true)"

now_epoch="$(date +%s)"

echo "[certs] Debug: now_epoch: '$now_epoch'"
echo "[certs] Debug: parsed end_epoch: '$end_epoch'"

if [ -z "$end_epoch" ]; then
  # BusyBox date on Alpine: fallback parsing with original enddate if normalized fails
  end_epoch="$(date -D '%b %e %T %Y %Z' -d "$enddate" +%s 2>/dev/null || true)"
  echo "[certs] Debug: Attempted BusyBox explicit format parsing with original enddate. end_epoch: $end_epoch"
fi

if [ -z "$end_epoch" ]; then
  echo "[certs] WARNING: Could not parse certificate end date; treating as invalid"
  exit 1
fi
echo "[certs] Debug: Date parsing successful."

secs_left=$(( end_epoch - now_epoch ))
days_left=$(( secs_left / 86400 ))
echo "[certs] Certificate expires in ~${days_left} days"

if [ "$days_left" -lt "$min_days_left" ]; then
  echo "[certs] Expiring soon (< ${min_days_left} days)"
  exit 1
fi

# Check SAN coverage
echo "[certs] Debug: Checking SAN coverage."
echo "[certs] Verifying SANs cover DOMAIN and aliases…"
sans="$(openssl x509 -noout -text -in "$FULLCHAIN" | awk '/Subject Alternative Name/{flag=1;next}/X509v3/{flag=0}flag' | tr -d ' ')"
need_ok=1

has_name() {
  needle="$1"
  echo "$sans" | grep -q "DNS:$needle"
}
echo "[certs] Debug: Raw SANs from openssl: '$sans'"
echo "[certs] Debug: DOMAIN_NAME: '$DOMAIN_NAME'"
echo "[certs] Debug: ALIASES: '$ALIASES'"

# Primary
if ! has_name "$DOMAIN_NAME"; then
  echo "[certs] Missing SAN for $DOMAIN_NAME"
  need_ok=0
fi
echo "[certs] Debug: Primary SAN check result: $need_ok (0=fail, 1=pass)"

# Aliases
for h in $ALIASES; do
  if ! has_name "$h"; then
    echo "[certs] Missing SAN for $h"
    need_ok=0
  fi
done
echo "[certs] Debug: Alias SAN check result: $need_ok (0=fail, 1=pass)"

[ "$need_ok" -eq 1 ] || { echo "[certs] SANs mismatch"; exit 1; }

echo "[certs] ✅ Cert OK (coverage + validity)"
exit 0