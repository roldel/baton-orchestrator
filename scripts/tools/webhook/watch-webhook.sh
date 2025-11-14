#!/bin/sh
# /opt/baton-orchestrator/scripts/tools/webhook/watch-webhook.sh
# Watches a directory for task_*.baton files and processes them via handle-webhook.sh

set -eu

# --- Configuration ---
WATCH_DIR="/srv/webhooks/signals/"
HANDLER="/opt/baton-orchestrator/scripts/tools/webhook/handle-webhook.sh"
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
  # Execute the handler, redirecting its stdout/stderr to the main log
  "$HANDLER" "$f" >>"$LOG" 2>&1 || log "Handler FAILED for $f (see log for details)"
}

# --- Startup message ---
log "Starting watcher in $WATCH_DIR ; handler=$HANDLER"

# --- Handle any backlog first (oldest first) ---
set +e # Temporarily disable exit on error for ls (in case dir is empty)
BACKLOG_LIST="$(ls -1tr "$WATCH_DIR"/$PATTERN 2>/dev/null || true)"
set -e # Re-enable exit on error
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
# We call inotifywait once per event. If this script gets SIGTERM from OpenRC,
# the shell and inotifywait will both exit, and OpenRC will be satisfied.

while :; do
  # Capture both stdout and stderr of inotifywait.
  # If inotifywait fails or is interrupted, its diagnostics might be on stderr.
  # We use a temporary file to capture output reliably across different shells.
  _inotify_output_file=$(mktemp)
  _inotify_exit_status=0

  if ! inotifywait -q -e close_write -e moved_to --format '%w%f' "$WATCH_DIR" >"$_inotify_output_file" 2>&1; then
    _inotify_exit_status=$?
    _error_content=$(cat "$_inotify_output_file")
    log "inotifywait exited with status $_inotify_exit_status. Output/Error: '$_error_content'"
    rm -f "$_inotify_output_file"
    # Exit if inotifywait genuinely failed, otherwise loop if it's just a non-event exit (e.g. interruption)
    # A status of 0 means success, >0 means some error or interruption.
    # In practice, OpenRC sending SIGTERM will cause it to exit with a non-zero status.
    # We exit the while loop so OpenRC can manage the service.
    exit 0 
  fi
  
  # If inotifywait succeeded, read the path from the temp file
  path=$(cat "$_inotify_output_file")
  rm -f "$_inotify_output_file"

  case "$(basename -- "$path")" in
    $PATTERN) process_file "$path" ;;
    *) log "Ignoring non-matching file or directory event: '$path'" ;; # Log unexpected events
  esac
done

# Not normally reached
exit 0