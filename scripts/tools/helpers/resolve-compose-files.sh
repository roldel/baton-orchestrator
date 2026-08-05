#!/bin/sh
# Resolve docker compose file(s) for a project directory.
#
# Usage:
#   resolve-compose-files.sh <project-dir> [explicit-file ...]
#
# Resolution order:
#   1. Explicit file arguments (CLI override for one-shot ops)
#   2. DOCKER_COMPOSE_FILES from <project-dir>/.env
#      (comma- or colon-separated; relative paths are relative to project dir)
#   3. Auto-detect a single conventional filename:
#        docker-compose.yml | docker-compose.yaml | compose.yml | compose.yaml
#
# Prints absolute paths, one per line (order preserved — later files override
# earlier ones under Compose merge rules).
# Exits non-zero if none found or any listed file is missing.
#
# Note: when any -f is passed to `docker compose`, override files are NOT
# auto-loaded. List every file you need via DOCKER_COMPOSE_FILES (or args).

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-dir> [compose-file ...]" >&2
  exit 1
fi

LOOKUP_PATH="$1"
shift

if [ ! -d "$LOOKUP_PATH" ]; then
  echo "[resolve-compose] ERROR: Directory not found: $LOOKUP_PATH" >&2
  exit 1
fi

# Normalize to an absolute path (prevents "./" issues)
PROJECT_DIR="$(cd "$LOOKUP_PATH" && pwd)"

# --- Collect raw entries into a newline-separated list ---
RAW_ENTRIES=""

append_raw() {
  _raw="$1"
  case "$_raw" in
    '') return 0 ;;
  esac
  if [ -n "$RAW_ENTRIES" ]; then
    RAW_ENTRIES="$RAW_ENTRIES
$_raw"
  else
    RAW_ENTRIES="$_raw"
  fi
}

if [ "$#" -gt 0 ]; then
  # Explicit CLI/args override
  for f in "$@"; do
    append_raw "$f"
  done
else
  # Read DOCKER_COMPOSE_FILES from .env without polluting this shell
  ENV_FILE="$PROJECT_DIR/.env"
  COMPOSE_LIST=""
  if [ -f "$ENV_FILE" ]; then
    COMPOSE_LIST="$(
      set +eu
      # shellcheck source=/dev/null
      . "$ENV_FILE" >/dev/null 2>&1
      printf '%s' "${DOCKER_COMPOSE_FILES:-}"
    )"
  fi

  if [ -n "$COMPOSE_LIST" ]; then
    # Split on comma or colon; trim whitespace around each entry
    _normalized="$(printf '%s' "$COMPOSE_LIST" | tr ',:' '\n\n')"
    while IFS= read -r entry || [ -n "$entry" ]; do
      entry="$(printf '%s' "$entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -n "$entry" ] || continue
      append_raw "$entry"
    done <<EOF
$_normalized
EOF
  else
    # Auto-detect single conventional compose filename
    for name in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
      if [ -f "$PROJECT_DIR/$name" ]; then
        append_raw "$name"
        break
      fi
    done
    if [ -z "$RAW_ENTRIES" ]; then
      echo "[resolve-compose] ERROR: No docker compose file found in $PROJECT_DIR" >&2
      echo "[resolve-compose] Tried auto-detect:" >&2
      for name in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        echo "  - $name" >&2
      done
      echo "[resolve-compose] Or set DOCKER_COMPOSE_FILES in $PROJECT_DIR/.env" >&2
      exit 1
    fi
  fi
fi

if [ -z "$RAW_ENTRIES" ]; then
  echo "[resolve-compose] ERROR: No compose files resolved for $PROJECT_DIR" >&2
  exit 1
fi

# --- Resolve to absolute paths, validate existence, print ---
OUTPUT=""
while IFS= read -r entry || [ -n "$entry" ]; do
  [ -n "$entry" ] || continue

  case "$entry" in
    /*) ABS="$entry" ;;
    *)  ABS="$PROJECT_DIR/$entry" ;;
  esac

  if [ ! -f "$ABS" ]; then
    echo "[resolve-compose] ERROR: Compose file not found: $ABS" >&2
    exit 1
  fi

  ABS="$(cd "$(dirname "$ABS")" && pwd)/$(basename "$ABS")"

  if [ -n "$OUTPUT" ]; then
    OUTPUT="$OUTPUT
$ABS"
  else
    OUTPUT="$ABS"
  fi
done <<EOF
$RAW_ENTRIES
EOF

if [ -z "$OUTPUT" ]; then
  echo "[resolve-compose] ERROR: No compose files resolved for $PROJECT_DIR" >&2
  exit 1
fi

printf '%s\n' "$OUTPUT"
