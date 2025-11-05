#!/bin/sh
# Purge a project: nginx confs, certs, shared files, optional project dir
# Usage: baton purge <project> [--yes] [--dry-run] [--keep-project] [--keep-shared] [--keep-certs]
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via 'baton purge <project>'"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

# -------- Args --------
proj="${1:-}"; shift || true
[ -n "$proj" ] || { echo "Usage: baton purge <project> [--yes] [--dry-run] [--keep-project] [--keep-shared] [--keep-certs]"; exit 1; }

YES=0
DRY_RUN=0
KEEP_PROJECT=0
KEEP_SHARED=0
KEEP_CERTS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --keep-project) KEEP_PROJECT=1 ;;
    --keep-shared)  KEEP_SHARED=1 ;;
    --keep-certs)   KEEP_CERTS=1 ;;
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
  # Preferred: from .env
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
# safety: only remove files under $CONF_DIR matching domain patterns
conf_globs="
$CONF_DIR/${DOMAIN}.conf
$CONF_DIR/${DOMAIN}.conf.disabled.*
$CONF_DIR/${DOMAIN}.conf.bak.*
$CONF_DIR/.${DOMAIN}.conf.tmp.*
$CONF_DIR/.${DOMAIN}.conf.rendered.*
"

shared_root="${SHARED_FILES%/}"
shared_dir="$shared_root/$DOMAIN"            # may contain /static and /media underneath

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

mv_path() {
  src="$1"; dst="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] mv -- $src $dst"
  else
    mv -- "$src" "$dst"
  fi
}

reload_nginx() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] docker exec ingress-nginx nginx -s reload"
  else
    docker exec ingress-nginx nginx -s reload 2>/dev/null || true
  fi
}

# -------- Prompt --------
echo "About to PURGE project: $proj"
echo "  DOMAIN                : $DOMAIN"
echo "  Nginx conf (primary)  : $live_conf"
echo "  Conf patterns         :"
printf "    - %s\n" $(echo "$conf_globs")
echo "  Shared files path     : $shared_dir"
echo "  Certs live/archive    : $cert_live | $cert_arch"
echo "  Cert renewal file     : $cert_renw"
echo "  Keep project dir      : $([ $KEEP_PROJECT -eq 1 ] && echo yes || echo no)"
echo "  Keep shared files     : $([ $KEEP_SHARED -eq 1 ] && echo yes || echo no)"
echo "  Keep certs            : $([ $KEEP_CERTS -eq 1 ] && echo yes || echo no)"
echo "  Dry run               : $([ $DRY_RUN -eq 1 ] && echo yes || echo no)"

if [ "$YES" -ne 1 ]; then
  printf "Type YES to continue: "
  read -r ans
  [ "$ans" = "YES" ] || { echo "Aborted."; exit 1; }
fi

# -------- Remove nginx confs (live + backups + temps) --------
echo "Removing Nginx conf(s)..."
for g in $conf_globs; do
  # Expand glob manually
  for f in $g; do
    [ -e "$f" ] || continue
    rm_path "$f"
  done
done

# Reload nginx to apply removal
echo "Reloading Nginx..."
reload_nginx

# -------- Remove shared files (unless kept) --------
if [ "$KEEP_SHARED" -eq 0 ]; then
  if [ -d "$shared_dir" ]; then
    echo "Removing shared files: $shared_dir"
    rm_path "$shared_dir"
  else
    echo "Shared files not present: $shared_dir"
  fi
else
  echo "Keeping shared files: $shared_dir"
fi

# -------- Remove certificates (unless kept) --------
if [ "$KEEP_CERTS" -eq 0 ]; then
  echo "Removing certificates for $DOMAIN..."
  [ -d "$cert_live" ] && rm_path "$cert_live" || echo "No live/ dir for $DOMAIN"
  [ -d "$cert_arch" ] && rm_path "$cert_arch" || echo "No archive/ dir for $DOMAIN"
  [ -f "$cert_renw" ] && rm_path "$cert_renw" || echo "No renewal file for $DOMAIN"
else
  echo "Keeping certificates for $DOMAIN"
fi

# -------- Remove project dir (unless kept) --------
if [ "$KEEP_PROJECT" -eq 0 ]; then
  echo "Removing project directory: $proj_dir"
  rm_path "$proj_dir"
else
  echo "Keeping project directory: $proj_dir"
fi

echo
echo "Purge complete for project: $proj"
[ "$DRY_RUN" -eq 1 ] && echo "(dry-run: no changes were made)"
