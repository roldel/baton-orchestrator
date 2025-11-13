#!/bin/sh
# Detects the docker compose file inside a directory.
# Supports multiple naming conventions:
#   docker-compose.yml / docker-compose.yaml
#   compose.yml / compose.yaml
#
# Prints the absolute file path to stdout if found.
# Exits with error if none found.

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <lookup-directory>" >&2
  exit 1
fi

LOOKUP_PATH="$1"

if [ ! -d "$LOOKUP_PATH" ]; then
  echo "[detect-compose] ERROR: Directory not found: $LOOKUP_PATH" >&2
  exit 1
fi

# Normalize to an absolute path (prevents "./" issues)
PROJECT_DIR="$(cd "$LOOKUP_PATH" && pwd)"

# List of allowed compose filenames (priority order)
CANDIDATES="
docker-compose.yml
docker-compose.yaml
compose.yml
compose.yaml
"

FOUND=""

for name in $CANDIDATES; do
  if [ -f "$PROJECT_DIR/$name" ]; then
    FOUND="$PROJECT_DIR/$name"
    break
  fi
done

if [ -z "$FOUND" ]; then
  echo "[detect-compose] ERROR: No docker compose file found in $PROJECT_DIR" >&2
  echo "[detect-compose] Tried:" >&2
  for name in $CANDIDATES; do
    echo "  - $name" >&2
  done
  exit 1
fi

# Print only the file path (stdout). Everything else goes to stderr.
echo "$FOUND"
