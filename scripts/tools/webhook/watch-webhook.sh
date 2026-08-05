#!/bin/sh
# watch-webhook.sh — durable queue worker for webhook redeploy tasks
#
# Layout under /srv/webhooks/:
#   queue/        pending tasks (Flask writes task_*.baton here)
#   processing/   at most one claimed task while a redeploy runs
#   processed/    success / failure archive (handler moves files here)
#   failed/       tasks left behind after abnormal handler exit
#
# Reliability model:
#   - Tasks are durable files; HTTP returns after the file is renamed into queue/
#   - A single worker claims with `mv queue → processing` (exclusive)
#   - Hybrid wait: drain the queue fully, then inotifywait with timeout so a
#     missed event can never leave work stranded (poll fallback)
#   - On startup, reclaim anything left in processing/ and migrate legacy
#     /srv/webhooks/signals/ into queue/

set -eu

# --- Config ---
WEBHOOKS_ROOT="/srv/webhooks"
QUEUE_DIR="${WEBHOOKS_ROOT}/queue"
PROCESSING_DIR="${WEBHOOKS_ROOT}/processing"
PROCESSED_DIR="${WEBHOOKS_ROOT}/processed"
FAILED_DIR="${WEBHOOKS_ROOT}/failed"
LEGACY_SIGNALS_DIR="${WEBHOOKS_ROOT}/signals"

HANDLER="/opt/baton-orchestrator/scripts/tools/webhook/handle-webhook.sh"
LOG="/var/log/baton-webhook.log"
PATTERN='task_*.baton'
# Seconds to block in inotifywait when the queue is empty (then re-scan)
INOTIFY_TIMEOUT_SEC="${BATON_WEBHOOK_POLL_SEC:-30}"

# --- Simple logging ---
log() {
  printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"
}

# --- Dependency check ---
need() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR: Missing required command: $1"
    exit 1
  }
}

is_task_file() {
  case "$(basename -- "$1")" in
    $PATTERN) return 0 ;;
    *) return 1 ;;
  esac
}

# Move every task_*.baton from SRC into QUEUE (no-op if SRC missing/empty)
migrate_dir_into_queue() {
  _src="$1"
  _label="$2"
  [ -d "$_src" ] || return 0

  _moved=0
  # find + sort for stable order; read line-by-line (no word-splitting)
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    base="$(basename -- "$f")"
    dest="$QUEUE_DIR/$base"
    # Avoid clobbering an existing queued task with the same name
    if [ -e "$dest" ]; then
      dest="$QUEUE_DIR/${base}.reclaimed.$(date +%s).$$"
    fi
    if mv "$f" "$dest" 2>/dev/null; then
      _moved=$((_moved + 1))
    else
      log "WARNING: could not migrate $f → $dest"
    fi
  done <<EOF
$(find "$_src" -maxdepth 1 -type f -name "$PATTERN" 2>/dev/null | sort)
EOF

  if [ "$_moved" -gt 0 ]; then
    log "Migrated $_moved task(s) from $_label into queue"
  fi
}

# Read PROJECT= from a task file (first matching line). Empty if missing.
task_project() {
  _tf="$1"
  _proj=""
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      PROJECT=*)
        _proj="${_line#PROJECT=}"
        # strip optional quotes
        _proj="${_proj%\"}"; _proj="${_proj#\"}"
        _proj="${_proj%\'}"; _proj="${_proj#\'}"
        break
        ;;
    esac
  done < "$_tf"
  printf '%s' "$_proj"
}

# Collapse multiple pending tasks for the same project into the newest one.
# Older duplicates are archived under processed/ as .coalesced.<ts> so a push
# storm does not stack redundant full redeploys. Newest = last in sort order
# (task filenames are timestamp-prefixed).
#
# Implementation: walk tasks in sorted order, overwrite a per-project winner
# path in a temp dir (last write wins). Then drop any queue file that is not
# its project's winner.
coalesce_queue() {
  _list="$(find "$QUEUE_DIR" -maxdepth 1 -type f -name "$PATTERN" 2>/dev/null | sort)"
  [ -n "$_list" ] || return 0

  _count=0
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    _count=$((_count + 1))
  done <<EOF
$_list
EOF
  # Nothing to coalesce with fewer than 2 tasks
  [ "$_count" -ge 2 ] || return 0

  _windir="$(mktemp -d /tmp/baton-coalesce.XXXXXX)" || return 0

  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    _p="$(task_project "$f")"
    [ -n "$_p" ] || _p="__unknown__"
    # Stable, filesystem-safe key for the project name
    _key="$(printf '%s' "$_p" | cksum | awk '{print $1}')"
    # Record absolute path of current winner (last in sort order)
    printf '%s\n' "$f" > "$_windir/$_key"
  done <<EOF
$_list
EOF

  _dropped=0
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    _p="$(task_project "$f")"
    [ -n "$_p" ] || _p="__unknown__"
    _key="$(printf '%s' "$_p" | cksum | awk '{print $1}')"
    _winner=""
    if [ -f "$_windir/$_key" ]; then
      _winner="$(cat "$_windir/$_key")"
    fi
    if [ -n "$_winner" ] && [ "$f" != "$_winner" ]; then
      _base="$(basename -- "$f")"
      _dest="$PROCESSED_DIR/${_base}.coalesced.$(date +%s).$$"
      if mv "$f" "$_dest" 2>/dev/null; then
        _dropped=$((_dropped + 1))
        log "Coalesced (dropped older duplicate): $_base"
      fi
    fi
  done <<EOF
$_list
EOF

  rm -rf "$_windir"

  if [ "$_dropped" -gt 0 ]; then
    log "Coalesced $_dropped older task(s); keeping newest per project"
  fi
}

# Claim the oldest pending task into processing/. Prints claimed path or nothing.
claim_next_task() {
  next="$(find "$QUEUE_DIR" -maxdepth 1 -type f -name "$PATTERN" 2>/dev/null | sort | head -n 1)"
  if [ -z "$next" ] || [ ! -f "$next" ]; then
    return 0
  fi

  base="$(basename -- "$next")"
  claimed="$PROCESSING_DIR/$base"
  if [ -e "$claimed" ]; then
    claimed="$PROCESSING_DIR/${base}.$$"
  fi

  # Exclusive claim via rename; if it fails another worker raced us
  if mv "$next" "$claimed" 2>/dev/null; then
    printf '%s\n' "$claimed"
  fi
}

process_claimed() {
  f="$1"
  [ -f "$f" ] || return 0
  is_task_file "$f" || {
    log "Ignoring non-task file in processing: $f"
    return 0
  }

  log "Processing: $f"
  if "$HANDLER" "$f" >>"$LOG" 2>&1; then
    log "Success: $f"
  else
    log "FAILED: $f (code $?)"
  fi

  # If the handler crashed/exited without archiving the task file, park it
  # under failed/ so it is not reclaimed into an infinite crash loop without
  # visibility. Operators can re-queue manually if needed.
  if [ -f "$f" ]; then
    base="$(basename -- "$f")"
    dest="$FAILED_DIR/${base}.stranded.$(date +%s)"
    log "WARNING: task still in processing after handler exit — moving to $dest"
    mv "$f" "$dest" 2>/dev/null || true
  fi
}

# Drain queue until empty
drain_queue() {
  # Collapse push storms before claiming so we never run N redeploys for
  # the same project when only the latest state matters.
  coalesce_queue
  while true; do
    claimed="$(claim_next_task || true)"
    if [ -z "$claimed" ]; then
      break
    fi
    process_claimed "$claimed"
    # After each task, re-coalesce: new pushes may have arrived mid-redeploy
    coalesce_queue
  done
}

# --- Validate ---
need inotifywait
need find
need sort
need head

[ -x "$HANDLER" ] || { log "ERROR: Handler not executable: $HANDLER"; exit 1; }

mkdir -p "$QUEUE_DIR" "$PROCESSING_DIR" "$PROCESSED_DIR" "$FAILED_DIR"

# --- Startup ---
log "Watcher started (queue=$QUEUE_DIR)"

# Crash recovery: unfinished claims go back to the queue
migrate_dir_into_queue "$PROCESSING_DIR" "processing/"

# Backward compatibility: tasks written to the old signals/ path
migrate_dir_into_queue "$LEGACY_SIGNALS_DIR" "legacy signals/"

# --- Clean shutdown ---
trap 'log "Shutting down..."; exit 0' TERM INT

# Initial drain (covers backlog + reclaimed tasks)
log "Draining queue..."
drain_queue
log "Queue empty — waiting for new tasks (inotify + ${INOTIFY_TIMEOUT_SEC}s poll)"

# --- MAIN LOOP ---
# Hybrid: inotify wakes us quickly on new files; timeout forces a re-scan so a
# race between drain and watch can never drop a task permanently.
while true; do
  # Block until an event or timeout. Exit codes: 0=event, 1=error, 2=timeout
  # (inotify-tools). We always re-drain afterward.
  inotifywait -t "$INOTIFY_TIMEOUT_SEC" -q \
    -e close_write -e moved_to \
    --format '%w%f' \
    "$QUEUE_DIR" >>"$LOG" 2>&1 || true

  drain_queue
done
