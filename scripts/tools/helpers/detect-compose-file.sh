#!/bin/sh
# Backward-compatible wrapper around resolve-compose-files.sh.
#
# Historical behaviour: print a single compose file path.
# If multiple files are configured (DOCKER_COMPOSE_FILES), prints the *first*
# file only and warns on stderr. Prefer resolve-compose-files.sh or
# compose-cmd.sh for multi-file stacks.
#
# Usage:
#   detect-compose-file.sh <project-dir>

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <lookup-directory>" >&2
  exit 1
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
RESOLVE="$SCRIPT_DIR/resolve-compose-files.sh"

if [ ! -f "$RESOLVE" ]; then
  echo "[detect-compose] ERROR: resolve-compose-files helper not found: $RESOLVE" >&2
  exit 1
fi

FILE_LIST="$(sh "$RESOLVE" "$1")"
FIRST=""
COUNT=0
while IFS= read -r f || [ -n "$f" ]; do
  [ -n "$f" ] || continue
  COUNT=$((COUNT + 1))
  if [ -z "$FIRST" ]; then
    FIRST="$f"
  fi
done <<EOF
$FILE_LIST
EOF

if [ -z "$FIRST" ]; then
  echo "[detect-compose] ERROR: No docker compose file resolved" >&2
  exit 1
fi

if [ "$COUNT" -gt 1 ]; then
  echo "[detect-compose] WARNING: $COUNT compose files configured; only reporting the first." >&2
  echo "[detect-compose]          Use resolve-compose-files.sh / compose-cmd.sh for full multi-file support." >&2
fi

echo "$FIRST"
