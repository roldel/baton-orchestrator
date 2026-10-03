#!/bin/sh
# Renew Let's Encrypt certificates and reload nginx when a live certificate
# file changes. Certbot's exit status is kept: a failed renew is never logged
# as "No renewal needed." The transcript goes to the log file. On failure one
# line is also written to stderr so cron has something to report.

set -eu

LOGFILE="/var/log/baton-cert-renew.log"
BASE_DIR="/opt/baton-orchestrator"
LIVE_DIR="/etc/letsencrypt/live"
ORCHESTRATOR_COMPOSE="$BASE_DIR/orchestrator/docker-compose.yml"
RELOAD_SH="$BASE_DIR/scripts/tools/nginx/reload.sh"

mkdir -p /var/log
touch "$LOGFILE" || { echo "ERROR: Could not create log file: $LOGFILE" >&2; exit 1; }
chmod 644 "$LOGFILE"

# Sorted "hash  path" lines for every live fullchain.pem.
# An unreadable file is recorded so a later change still shows up.
cert_checksums() {
  _out="$1"
  : > "$_out"
  if [ ! -d "$LIVE_DIR" ]; then
    return 0
  fi
  _list="$_out.list"
  find "$LIVE_DIR" -mindepth 2 -maxdepth 2 -name fullchain.pem | sort > "$_list"
  while IFS= read -r _cert; do
    [ -n "$_cert" ] || continue
    if ! sha256sum "$_cert" >> "$_out"; then
      echo "UNREADABLE $_cert" >> "$_out"
    fi
  done < "$_list"
  rm -f "$_list"
}

renew_main() {
  echo "----- $(date '+%Y-%m-%d %H:%M:%S') Starting renewal -----"

  if ! command -v sha256sum >/dev/null 2>&1; then
    echo "[renew] ERROR: sha256sum not found." >&2
    echo "----- $(date '+%Y-%m-%d %H:%M:%S') Done -----"
    return 1
  fi

  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/baton-cert-renew.XXXXXX")"
  trap 'rm -rf "$_tmp"' EXIT INT TERM

  cert_checksums "$_tmp/before"

  echo "[renew] Running certbot renew..."
  set +e
  OUTPUT="$(docker compose -f "$ORCHESTRATOR_COMPOSE" run --rm certbot renew 2>&1)"
  CERTBOT_STATUS=$?
  set -e
  printf '%s\n' "$OUTPUT"

  cert_checksums "$_tmp/after"

  FAIL=0
  if cmp -s "$_tmp/before" "$_tmp/after"; then
    CHANGED=0
  else
    CHANGED=1
    echo "[renew] Certificate files changed → reloading nginx..."
    if ! sh "$RELOAD_SH"; then
      echo "[renew] ERROR: nginx reload failed after certificate change." >&2
      FAIL=1
    fi
  fi

  if [ "$CERTBOT_STATUS" -ne 0 ]; then
    echo "[renew] ERROR: certbot renew exited $CERTBOT_STATUS." >&2
    FAIL=1
  elif [ "$CHANGED" -eq 0 ]; then
    echo "[renew] No renewal needed."
  fi

  echo "----- $(date '+%Y-%m-%d %H:%M:%S') Done -----"

  if [ "$FAIL" -ne 0 ]; then
    return 1
  fi
  return 0
}

if ! renew_main >> "$LOGFILE" 2>&1; then
  echo "ERROR: certificate renewal failed. See $LOGFILE" >&2
  exit 1
fi
