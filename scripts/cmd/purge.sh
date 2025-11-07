#!/bin/sh
# Purge a project: remove caddy confs (live/disabled/tmp/backups) and certificates.
# Optionally delete shared files and/or the project repo directory after prompts.
#
# Usage:
#   baton purge <project> [--yes] [--dry-run]
#                      [--delete-shared | --keep-shared]
#                      [--delete-project | --keep-project]
#
# Notes:
#   - ALWAYS removes: Caddy conf files for the domain + Let's Encrypt certs for the domain
#   - Shared files deletion is OPTIONAL and PROMPTED (unless flag provided)
#   - Project repo deletion is OPTIONAL and PROMPTED (unless flag provided)
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via 'baton purge <project>'"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

# -------- Args --------
proj="${1:-}"; shift || true
[ -n "$proj" ] || { echo "Usage: baton purge <project> [--yes] [--dry-run] [--delete-shared|--keep-shared] [--delete-project|--keep-project]"; exit 1; }

YES=0
DRY_RUN=0
DELETE_SHARED_FLAG=""   # "", "delete", or "keep"
DELETE_PROJECT_FLAG=""  # "", "delete", or "keep"

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --delete-shared)  DELETE_SHARED_FLAG="delete" ;;
    --keep-shared)    DELETE_SHARED_FLAG="keep" ;;
    --delete-project) DELETE_PROJECT_FLAG="delete" ;;
    --keep-project)   DELETE_PROJECT_FLAG="keep" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift || true
done

# -------- Resolve project + domain --------
proj_dir="$PROJECTS_DIR/$proj"
conf_file="$proj_dir/server.conf"
env_file="$proj_dir/.env"

[ -d "$proj_dir" ]  || { echo "ERROR: Project directory not found: $proj_dir" >&2; exit 1; }
[ -f "$conf_file" ] || { echo "ERROR: Missing server.conf in $proj_dir" >&2; exit 1; }

if [ -f "$env_file" ]; then
  load_dotenv "$env_file" >/dev/null
  DOMAIN="$DOMAIN_NAME"
else
  echo "ERROR: Could not find .env to determine domain for project $proj" >&2
  exit 1
fi

# -------- Targets --------
live_conf="$CONF_DIR/${DOMAIN}.conf"
conf_globs="
$CONF_DIR/${DOMAIN}.conf
$CONF_DIR/${DOMAIN}.conf.disabled.*
$CONF_DIR/${DOMAIN}.conf.bak.*
$CONF_DIR/.${DOMAIN}.conf.tmp.*
$CONF_DIR/.${DOMAIN}.conf.rendered.*
"

shared_root="${SHARED_FILES%/}"
shared_dir="$shared_root/$DOMAIN"  # e.g., /shared-files/example.com (contains static/, media/)

# Note: Caddy certificate paths are different from nginx/certbot.
# Caddy manages them internally in its /data volume. Purging the config and reloading
# is usually enough. For a full wipe, caddy's data volume would need to be cleared.
# This script focuses on the configs which is safer.

# -------- Helpers --------
rm_path() {
  p="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] rm -rf -- $p"
  else
    rm -rf -- "$p" 2>/dev/null || true
  fi
}

reload_caddy() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] docker exec ingress-caddy caddy reload --config /etc/caddy/Caddyfile"
  else
    # || true is okay here, as Caddy might not be running but we still want to clean up files.
    docker exec ingress-caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
  fi
}

# -------- Summary & main confirmation --------
echo "About to PURGE config for project: $proj"
echo "  DOMAIN                : $DOMAIN"
echo "  Caddy conf root       : $CONF_DIR"
echo "  Will remove patterns  :"
printf "    - %s\n" $(echo "$conf_globs")
echo "  Shared files path     : $shared_dir (separate prompt)"
echo "  Project directory     : $proj_dir (separate prompt)"
echo "  Dry run               : $([ $DRY_RUN -eq 1 ] && echo yes || echo no)"

if [ "$YES" -ne 1 ]; then
  printf "Type YES to remove the above Caddy configs: "
  read -r ans
  [ "$ans" = "YES" ] || { echo "Aborted."; exit 1; }
fi

# -------- Remove Caddy confs (live + backups + temps) --------
echo "Removing Caddy conf(s)..."
for g in $conf_globs; do
  for f in $g; do
    [ -e "$f" ] || continue
    rm_path "$f"
  done
done

# Reload Caddy to apply removal
echo "Reloading Caddy..."
reload_caddy

# -------- Prompt for shared files deletion (intermediate prompt) --------
DELETE_SHARED=0
case "$DELETE_SHARED_FLAG" in
  delete) DELETE_SHARED=1 ;;
  keep)   DELETE_SHARED=0 ;;
  "")
    if [ -d "$shared_dir" ]; then
      printf "Also delete shared static/media under '%s'? [y/N]: " "$shared_dir"
      read -r del_shared
      case "$del_shared" in
        y|Y|yes|YES) DELETE_SHARED=1 ;;
        *) DELETE_SHARED=0 ;;
      esac
    else
      echo "Shared files not present: $shared_dir"
      DELETE_SHARED=0
    fi
    ;;
esac

if [ "$DELETE_SHARED" -eq 1 ]; then
  echo "Deleting shared files: $shared_dir"
  rm_path "$shared_dir"
else
  echo "Keeping shared files: $shared_dir"
fi

# -------- Prompt for project directory deletion (final prompt) --------
DELETE_PROJECT=0
case "$DELETE_PROJECT_FLAG" in
  delete) DELETE_PROJECT=1 ;;
  keep)   DELETE_PROJECT=0 ;;
  "")
    printf "Also delete the project repository directory?\n  %s\nConfirm delete of '%s'? [y/N]: " "$proj_dir" "$proj_dir"
    read -r del_proj
    case "$del_proj" in
      y|Y|yes|YES) DELETE_PROJECT=1 ;;
      *) DELETE_PROJECT=0 ;;
    esac
    ;;
esac

if [ "$DELETE_PROJECT" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] rm -rf -- $proj_dir"
  else
    rm -rf -- "$proj_dir"
  fi
  echo "Project directory removed: $proj_dir"
else
  echo "Project directory kept: $proj_dir"
fi

echo
echo "Purge complete for project: $proj"
[ "$DRY_RUN" -eq 1 ] && echo "(dry-run: no changes were made)"
