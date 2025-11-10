# File: scripts/start-webhook-watcher.sh
#!/bin/sh
set -eu

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SIGNAL_DIR="$BASE_DIR/orchestrator/webhook-redeploy-instruct"
HANDLE="$BASE_DIR/scripts/tools/webhook/handle-webhook.sh"

echo "Starting webhook watcher..."
echo "Watching: $SIGNAL_DIR"
echo "Press Ctrl+C to stop"

mkdir -p "$SIGNAL_DIR"

inotifywait -m -e create --format '%w%f' "$SIGNAL_DIR" 2>/dev/null | \
while IFS= read -r file; do
    if echo "$file" | grep -q '\.baton$'; then
        echo ""
        echo "New task: $file"
        "$HANDLE" "$file"
    fi
done