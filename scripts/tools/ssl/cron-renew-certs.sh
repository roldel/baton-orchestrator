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
TEST_CONFIG_SH="$BASE_DIR/scripts/tools/nginx/test-config.sh"
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

  # Checked explicitly with `||` (belt-and-suspenders with the plain, un-
  # conditional top-level call below, which is what actually keeps errexit
  # active through this whole function — see the comment there).
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/baton-cert-renew.XXXXXX")" || {
    echo "[renew] ERROR: mktemp failed to create a temp directory." >&2
    return 1
  }

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
    echo "[renew] Certificate files changed → testing nginx config before reload..."
    # reload.sh documents that it assumes `nginx -t` already passed; every
    # other caller in this codebase (stand-down.sh, webhook-activate.sh) runs
    # the test first, but this script previously didn't — so a config left
    # broken by something unrelated would make reload.sh's signal a silent
    # no-op against the still-broken config.
    if ! sh "$TEST_CONFIG_SH"; then
      echo "[renew] ERROR: nginx config test failed; skipping reload (config was already broken before this renewal)." >&2
      FAIL=1
    elif ! sh "$RELOAD_SH"; then
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

# Cleanup + failure reporting for renew_main, via a top-level EXIT trap
# rather than `if ! renew_main`. Calling a function as the condition of
# `if`/`!` (or of `&&`/`||`/`while`) suspends errexit for that call's *entire*
# body in bash/dash — not just the call site — so e.g. a failing `find`/`sort`
# inside cert_checksums(), or any other unguarded command, would silently
# continue instead of aborting. Calling renew_main as a plain statement below
# keeps -e genuinely active throughout its whole call tree; the EXIT trap
# (which always runs, including when -e triggers the exit) does the reporting
# that the old `if !` wrapper used to.
_tmp=""
on_exit() {
  _status=$?
  [ -n "$_tmp" ] && rm -rf "$_tmp"
  if [ "$_status" -ne 0 ]; then
    echo "ERROR: certificate renewal failed. See $LOGFILE" >&2
  fi
}
trap on_exit EXIT
trap 'exit 1' INT TERM

renew_main >> "$LOGFILE" 2>&1
