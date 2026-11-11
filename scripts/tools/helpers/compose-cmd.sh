#!/bin/sh
# Run `docker compose` for a project with the correctly resolved -f file list.
#
# Usage:
#   compose-cmd.sh <project-dir> <compose-subcommand-and-args...>
#   compose-cmd.sh <project-dir> --file <path> [--file <path> ...] -- <args...>
#   compose-cmd.sh <project-dir> --project <name> up -d ...
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
#
# `up` requires --project. The project's APP_SERVICE is attached to its own
# network baton-<project> through a generated override file, added after the
# compose guard has checked the project's own files. After `up`, the
# containers' real networks are checked; on a violation the project is taken
# down again. See project-network.sh.

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

BASE_DIR="${BATON_BASE_DIR:-/opt/baton-orchestrator}"
PROJECTS_ROOT="${BATON_PROJECTS_ROOT:-/srv/projects}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
RESOLVE="$SCRIPT_DIR/resolve-compose-files.sh"
. "$SCRIPT_DIR/compose-guard.sh"

if [ ! -f "$RESOLVE" ]; then
  echo "[compose-cmd] ERROR: resolve-compose-files helper not found: $RESOLVE" >&2
  exit 1
fi

# Optional explicit --file / -f overrides and --project before compose args
EXPLICIT_FILES=""
BATON_PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      if [ $# -lt 2 ]; then
        echo "[compose-cmd] ERROR: --project requires a project name" >&2
        exit 1
      fi
      BATON_PROJECT=$2
      shift 2
      ;;
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

IS_UP=0
[ "$1" = up ] && IS_UP=1
if [ "$IS_UP" -eq 1 ] && [ -z "$BATON_PROJECT" ]; then
  echo "[compose-cmd] ERROR: up requires --project <name> so the app joins its project network" >&2
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

# The override is written after the guard below; only its path goes in now.
# The guard checks the project's files alone, so a project can never declare
# baton's external network itself.
OVERRIDE=""
if [ "$IS_UP" -eq 1 ]; then
  . "$SCRIPT_DIR/project-network.sh"
  baton_upstream_host "$BATON_PROJECT" >/dev/null || exit 1
  OVERRIDE="$BASE_DIR/tmp/compose/$BATON_PROJECT.yml"
  set -- "$@" -f "$OVERRIDE"
  _files_log="$_files_log $OVERRIDE"
fi

_i=1
while [ "$_i" -le "$_carg_count" ]; do
  eval "set -- \"\$@\" \"\$_carg_$_i\""
  _i=$((_i + 1))
done

# config must succeed, and the rendered file must pass the host-escape scan,
# before compose runs. config stdout stays off this command's stdout.
_cfg=$(mktemp)
if ! (
  cd "$PROJECT_DIR" || exit 1
  set --
  while IFS= read -r _cf || [ -n "$_cf" ]; do
    [ -n "$_cf" ] || continue
    set -- "$@" -f "$_cf"
  done <<EOF
$FILE_LIST
EOF
  docker compose "$@" config
) >"$_cfg"; then
  rm -f "$_cfg"
  echo "[compose-cmd] ERROR: docker compose config failed for $PROJECT_DIR" >&2
  exit 1
fi
# Shared files live beside the project, at /srv/shared-files/<DOMAIN_NAME>.
_cg_shared=$(baton_compose_shared_dir "$PROJECT_DIR" "$SCRIPT_DIR") || _cg_shared=""
if ! baton_compose_config_allowed "$_cfg" "$PROJECT_DIR" "$_cg_shared"; then
  rm -f "$_cfg"
  exit 1
fi
rm -f "$_cfg"

if [ "$IS_UP" -eq 0 ]; then
  echo "[compose-cmd] dir=$PROJECT_DIR files:$_files_log" >&2
  cd "$PROJECT_DIR"
  exec docker compose "$@"
fi

# --- up: attach APP_SERVICE to the project network ---
APP_SERVICE="$(
  set +eu
  . "$SCRIPT_DIR/load-env-safe.sh"
  if load_env_safe "$PROJECTS_ROOT/$BATON_PROJECT/.env"; then
    printf '%s' "${APP_SERVICE:-}"
  fi
)"
if ! baton_check_app_service "$APP_SERVICE"; then
  echo "[compose-cmd] ERROR: APP_SERVICE in $PROJECTS_ROOT/$BATON_PROJECT/.env must name the compose service nginx proxies to ([A-Za-z0-9][A-Za-z0-9._-]*, not starting with baton-)" >&2
  exit 1
fi
_services=$(
  cd "$PROJECT_DIR" || exit 1
  set --
  while IFS= read -r _cf || [ -n "$_cf" ]; do
    [ -n "$_cf" ] || continue
    set -- "$@" -f "$_cf"
  done <<EOF
$FILE_LIST
EOF
  docker compose "$@" config --services
) || {
  echo "[compose-cmd] ERROR: could not list compose services for $PROJECT_DIR" >&2
  exit 1
}
if ! printf '%s\n' "$_services" | grep -qxF "$APP_SERVICE"; then
  echo "[compose-cmd] ERROR: APP_SERVICE '$APP_SERVICE' is not a service in the compose file(s)" >&2
  exit 1
fi
baton_network_write_override "$BATON_PROJECT" "$APP_SERVICE" "$OVERRIDE" || exit 1
baton_network_ensure "$BATON_PROJECT" || exit 1

echo "[compose-cmd] dir=$PROJECT_DIR files:$_files_log" >&2

cd "$PROJECT_DIR"
docker compose "$@"

# Check what Docker attached, not what the files said. Every container must
# sit only on this project's networks; otherwise take the project down.
set --
while IFS= read -r f || [ -n "$f" ]; do
  [ -n "$f" ] || continue
  set -- "$@" -f "$f"
done <<EOF
$FILE_LIST
EOF
set -- "$@" -f "$OVERRIDE"
if ! _ids=$(docker compose "$@" ps -a -q); then
  echo "[compose-cmd] ERROR: could not list containers to check their networks; taking $BATON_PROJECT down" >&2
  docker compose "$@" down || true
  exit 1
fi
# shellcheck disable=SC2086
if ! baton_network_verify "$BATON_PROJECT" $_ids; then
  echo "[compose-cmd] ERROR: network isolation check failed; taking $BATON_PROJECT down" >&2
  docker compose "$@" down || true
  exit 1
fi
