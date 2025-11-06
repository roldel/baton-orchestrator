#!/bin/sh
# Purge a project: remove nginx confs (live/disabled/tmp/backups) and certificates.
# Optionally delete shared files and/or the project repo directory after prompts.
#
# Usage:
#   baton purge <project> [--yes] [--dry-run]
#                      [--delete-shared | --keep-shared]
#                      [--delete-project | --keep-project]
#
# Notes:
#   - ALWAYS removes: Nginx conf files for the domain + Let's Encrypt certs for the domain
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
  load_dotenv "$env_file"
  DOMAIN="$DOMAIN_NAME"
else
  # Fallback: parse server_name (first token)
  eval "$("$SCRIPT_DIR/tools/domain-name-aliases-retriever.sh" "$conf_file")"
  DOMAIN="${MAIN_DOMAIN_NAME:-}"
  [ -n "$DOMAIN" ] || { echo "ERROR: Could not determine domain from server.conf" >&2; exit 1; }
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

certs_root="${CERTS_DIR%/}"
cert_live="$certs_root/live/$DOMAIN"
cert_arch="$certs_root/archive/$DOMAIN"
cert_renw="$certs_root/renewal/$DOMAIN.conf"

# -------- Helpers --------
rm_path() {
  p="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] rm -rf -- $p"
  else
    rm -rf -- $p 2>/dev/null || true
  fi
}

reload_nginx() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] docker exec ingress-nginx nginx -s reload"
  else
    docker exec ingress-nginx nginx -s reload 2>/dev/null || true
  fi
}

# -------- Summary & main confirmation --------
echo "About to PURGE config & certificates for project: $proj"
echo "  DOMAIN                : $DOMAIN"
echo "  Nginx conf root       : $CONF_DIR"
echo "  Will remove patterns  :"
printf "    - %s\n" $(echo "$conf_globs")
echo "  Certs live/archive    : $cert_live | $cert_arch"
echo "  Cert renewal file     : $cert_renw"
echo "  Shared files path     : $shared_dir (separate prompt)"
echo "  Project directory     : $proj_dir (separate prompt)"
echo "  Dry run               : $([ $DRY_RUN -eq 1 ] && echo yes || echo no)"

if [ "$YES" -ne 1 ]; then
  printf "Type YES to remove the above Nginx configs & certificates: "
  read -r ans
  [ "$ans" = "YES" ] || { echo "Aborted."; exit 1; }
fi

# -------- Remove nginx confs (live + backups + temps) --------
echo "Removing Nginx conf(s)..."
for g in $conf_globs; do
  for f in $g; do
    [ -e "$f" ] || continue
    rm_path "$f"
  done
done

# Reload nginx to apply removal
echo "Reloading Nginx..."
reload_nginx

# -------- Remove certificates --------
echo "Removing certificates for $DOMAIN..."
[ -d "$cert_live" ] && rm_path "$cert_live" || echo "No live/ dir for $DOMAIN"
[ -d "$cert_arch" ] && rm_path "$cert_arch" || echo "No archive/ dir for $DOMAIN"
[ -f "$cert_renw" ] && rm_path "$cert_renw" || echo "No renewal file for $DOMAIN"

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
