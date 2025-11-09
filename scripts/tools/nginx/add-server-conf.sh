#!/bin/sh
# Copy rendered server config into nginx/conf.d as <project>.conf
# Usage: add-server-conf.sh <project-name>
set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
SRC="$ROOT/orchestrator/server-confs/$PROJECT.conf"
DST_DIR="$ROOT/orchestrator/nginx/conf.d"
DST="$DST_DIR/$PROJECT.conf"

[ -r "$SRC" ] || { echo "ERROR: Missing rendered server conf: $SRC" >&2; exit 1; }
mkdir -p "$DST_DIR"

cp -f "$SRC" "$DST"
echo "[add-server-conf] Installed: $DST"
