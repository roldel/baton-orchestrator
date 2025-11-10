# /opt/baton-orchestrator/scripts/tools/webhook/watch_webhook.sh
#!/bin/sh
set -eu

BASE="/opt/baton-orchestrator"
WATCH="$BASE/orchestrator/webhook-redeploy-instruct"
HANDLER="$BASE/scripts/tools/webhook/handle_webhook.sh"
LOG="/var/log/baton-webhook.log"

log() { printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG"; }

# --- prep ---
mkdir -p "$WATCH" "$(dirname "$LOG")"
touch "$LOG" && chmod 664 "$LOG"
command -v inotifywait >/dev/null || { log "inotify-tools missing → apk add inotify-tools"; exit 1; }

log "Baton webhook watcher STARTED – watching $WATCH"

inotifywait -m -e create --format '%f' "$WATCH" | while read -r file; do
    [ "${file%.baton}" = "$file" ] && continue
    TASK="$WATCH/$file"
    log "New task: $TASK"
    sh "$HANDLER" "$TASK" >>"$LOG" 2>&1 && log "$TASK → OK" || log "$TASK → FAILED"
done