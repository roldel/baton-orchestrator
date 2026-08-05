#!/bin/sh
# Run `docker compose` for a project with the correctly resolved -f file list.
#
# Usage:
#   compose-cmd.sh <project-dir> <compose-subcommand-and-args...>
#   compose-cmd.sh <project-dir> --file <path> [--file <path> ...] -- <args...>
#
# Examples:
#   compose-cmd.sh /srv/projects/foo down
#   compose-cmd.sh /srv/projects/foo up -d --build --force-recreate
#   compose-cmd.sh /srv/projects/foo ps --status running --format '{{.Name}}'
#   compose-cmd.sh /srv/projects/foo --file docker-compose.yml --file override.yml -- up -d
#
# Always cds into the project directory so:
#   - docker compose picks up .env for ${VAR} interpolation
#   - relative paths inside compose files resolve correctly
#
# Compose files are resolved via resolve-compose-files.sh (see that helper for
# DOCKER_COMPOSE_FILES / auto-detect rules). Explicit --file flags override.

set -eu

if [ $# -lt 2 ]; then
  echo "Usage: $0 <project-dir> [--file <path> ...] [--] <compose-args...>" >&2
  exit 1
fi

LOOKUP_PATH="$1"
shift

if [ ! -d "$LOOKUP_PATH" ]; then
  echo "[compose-cmd] ERROR: Directory not found: $LOOKUP_PATH" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$LOOKUP_PATH" && pwd)"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
RESOLVE="$SCRIPT_DIR/resolve-compose-files.sh"

if [ ! -f "$RESOLVE" ]; then
  echo "[compose-cmd] ERROR: resolve-compose-files helper not found: $RESOLVE" >&2
  exit 1
fi

# Optional explicit --file / -f overrides before compose args
EXPLICIT_FILES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file|-f)
      if [ $# -lt 2 ]; then
        echo "[compose-cmd] ERROR: $1 requires a path argument" >&2
        exit 1
      fi
      EXPLICIT_FILES="$EXPLICIT_FILES
$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [ $# -lt 1 ]; then
  echo "[compose-cmd] ERROR: missing docker compose subcommand (e.g. up, down, ps)" >&2
  exit 1
fi

# Save compose subcommand args (positional params will be rebuilt for -f list)
_i=1
_n=$#
while [ "$_i" -le "$_n" ]; do
  eval "_carg_$_i=\$$_i"
  _i=$((_i + 1))
done
_carg_count=$_n

# Resolve file list
if [ -n "$EXPLICIT_FILES" ]; then
  set --
  while IFS= read -r _ef || [ -n "$_ef" ]; do
    [ -n "$_ef" ] || continue
    set -- "$@" "$_ef"
  done <<EOF
$EXPLICIT_FILES
EOF
  FILE_LIST="$(sh "$RESOLVE" "$PROJECT_DIR" "$@")"
else
  FILE_LIST="$(sh "$RESOLVE" "$PROJECT_DIR")"
fi

# Rebuild argv: -f file1 -f file2 ... <compose subcommand args>
set --
_files_log=""
while IFS= read -r f || [ -n "$f" ]; do
  [ -n "$f" ] || continue
  set -- "$@" -f "$f"
  _files_log="$_files_log $f"
done <<EOF
$FILE_LIST
EOF

if [ $# -eq 0 ]; then
  echo "[compose-cmd] ERROR: no compose files resolved for $PROJECT_DIR" >&2
  exit 1
fi

_i=1
while [ "$_i" -le "$_carg_count" ]; do
  eval "set -- \"\$@\" \"\$_carg_$_i\""
  _i=$((_i + 1))
done

echo "[compose-cmd] dir=$PROJECT_DIR files:$_files_log" >&2

cd "$PROJECT_DIR"
exec docker compose "$@"
