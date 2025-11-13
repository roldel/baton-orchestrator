#!/bin/sh
# /opt/baton-orchestrator/scripts/tools/webhook/watch_webhook.sh
# Watches a directory for task_*.baton files and processes them via handle_webhook.sh

set -eu

# --- Configuration ---
WATCH_DIR="/opt/baton-orchestrator/orchestrator/webhook-redeploy-instruct/"
HANDLER="/opt/baton-orchestrator/scripts/tools/webhook/handle_webhook.sh"
LOG="/var/log/baton-webhook.log"
PATTERN='task_*.baton'  # expected filename pattern

# --- Logging helper ---
log() {
  printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG"
}

# --- Dependency check ---
need() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Missing required command: $1"
    exit 1
  }
}

# --- Graceful shutdown handling ---
graceful_stop() {
  # This runs when OpenRC sends SIGTERM/SIGINT
  log "Shutdown signal received, stopping watcher…"
  # Exiting here ends the main shell; inotifywait + the pipeline will die when
  # their pipe is broken, so we don't need to micro-manage them.
  exit 0
}

trap graceful_stop INT TERM

# --- Basic validation ---
[ -d "$WATCH_DIR" ] || { log "Watch dir not found: $WATCH_DIR"; exit 1; }
[ -x "$HANDLER" ]   || { log "Handler not executable: $HANDLER"; exit 1; }
need inotifywait    # required for file monitoring

# --- File processor ---
process_file() {
  f="$1"
  # ensure file matches pattern and exists
  case "$(basename -- "$f")" in
    $PATTERN) : ;;
    *) return 0 ;;
  esac

  [ -f "$f" ] || return 0
  log "Detected task → $f"
  "$HANDLER" "$f" >>"$LOG" 2>&1 || log "Handler FAILED for $f (see log)"
}

# --- Startup message ---
log "Starting watcher in $WATCH_DIR ; handler=$HANDLER"

# --- Handle any backlog first (oldest first) ---
set +e
BACKLOG_LIST="$(ls -1tr "$WATCH_DIR"/$PATTERN 2>/dev/null || true)"
set -e
if [ -n "$BACKLOG_LIST" ]; then
  log "Backlog found; processing existing tasks..."
  echo "$BACKLOG_LIST" | while IFS= read -r f; do
    [ -n "$f" ] && process_file "$f"
  done
else
  log "No backlog to process."
fi

# --- Live monitoring loop ---
# close_write → file finished writing
# moved_to   → file atomically renamed into watch dir
inotifywait -m -q -e close_write -e moved_to \
  --format '%w%f' "$WATCH_DIR" | \
while IFS= read -r path; do
  case "$(basename -- "$path")" in
    $PATTERN) process_file "$path" ;;
  endac
done

log "Watcher stopping."
exit 0
