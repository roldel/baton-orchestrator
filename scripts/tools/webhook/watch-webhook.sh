#!/bin/sh
# watch-webhook.sh — minimal, robust, container-friendly

set -eu

# --- Config ---
WATCH_DIR="/srv/webhooks/signals/"
HANDLER="/opt/baton-orchestrator/scripts/tools/webhook/handle-webhook.sh"
LOG="/var/log/baton-webhook.log"
PATTERN='task_*.baton'

# --- Simple logging ---
log() {
  printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"
}

# --- Dependency check (keep this!) ---
need() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR: Missing required command: $1"
    exit 1
  }
}

# --- Validate ---
[ -d "$WATCH_DIR" ] || { log "ERROR: Watch dir missing: $WATCH_DIR"; exit 1; }
[ -x "$HANDLER" ]   || { log "ERROR: Handler not executable: $HANDLER"; exit 1; }
need inotifywait

# --- Process file ---
process_file() {
  local f="$1"
  case "$(basename -- "$f")" in
    $PATTERN) ;;
    *) return 0 ;;
  esac
  [ -f "$f" ] || return 0

  log "Processing: $f"
  if "$HANDLER" "$f" >>"$LOG" 2>&1; then
    log "Success: $f"
  else
    log "FAILED: $f (code $?)"
  fi
}

# --- Startup ---
log "Watcher started on $WATCH_DIR"

# --- Process backlog ---
if ls -1tr "$WATCH_DIR/$PATTERN" >/dev/null 2>&1; then
  log "Processing backlog..."
  for f in $(ls -1tr "$WATCH_DIR/$PATTERN"); do
    process_file "$f"
  done
else
  log "No backlog."
fi

# --- Clean shutdown ---
trap 'log "Shutting down..."; exit 0' TERM INT

# --- MAIN LOOP: inotifywait -m + while read (no exec 3) ---
log "Monitoring for new files..."

inotifywait -m -q --format '%w%f' -e close_write -e moved_to "$WATCH_DIR" 2>&1 |
while IFS= read -r path; do
  [ -n "$path" ] && process_file "$path"
done