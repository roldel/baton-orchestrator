#!/bin/sh
# Sync a project's built output into the shared-files location nginx serves
# from. Used for static sites, and for dynamic projects that also set
# STATIC_SOURCE_DIR (containers still run; server.conf serves this tree).
# Simple wholesale copy (no rsync/delta-checking): copies into a sibling temp
# directory, then atomically renames it into place, so nginx never serves an
# empty or half-copied directory if the copy is interrupted.
#
# Source:      /srv/projects/<project>/<STATIC_SOURCE_DIR>
# Destination: /srv/shared-files/<SITE_KEY>/site
#
# Prints the destination path to stdout.

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name>" >&2
  exit 1
fi

PROJECT="$1"

BASE_DIR="/opt/baton-orchestrator"
PROJECT_DIR="/srv/projects/$PROJECT"
ENV_FILE="$PROJECT_DIR/.env"
SHARED_FILES_ROOT="/srv/shared-files"

if [ ! -f "$ENV_FILE" ]; then
  echo "[sync-static-site] ERROR: Missing .env file: $ENV_FILE" >&2
  exit 1
fi

# Read STATIC_SOURCE_DIR in a subshell so the project file cannot replace BASE_DIR.
STATIC_SOURCE_DIR="$(
  set +eu
  . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
  if load_env_safe "$ENV_FILE"; then
    printf '%s' "${STATIC_SOURCE_DIR:-}"
  fi
)"

if [ -z "$STATIC_SOURCE_DIR" ]; then
  echo "[sync-static-site] ERROR: STATIC_SOURCE_DIR not set in $ENV_FILE" >&2
  exit 1
fi

SOURCE="$PROJECT_DIR/$STATIC_SOURCE_DIR"
if [ ! -d "$SOURCE" ]; then
  echo "[sync-static-site] ERROR: STATIC_SOURCE_DIR '$STATIC_SOURCE_DIR' not found at $SOURCE" >&2
  exit 1
fi

# The source must resolve inside the project directory.
RESOLVED_SOURCE="$(cd "$SOURCE" && pwd -P)"
RESOLVED_PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
case "$RESOLVED_SOURCE" in
  "$RESOLVED_PROJECT_DIR"|"$RESOLVED_PROJECT_DIR"/*) ;;
  *)
    echo "[sync-static-site] ERROR: STATIC_SOURCE_DIR '$STATIC_SOURCE_DIR' resolves outside the project directory: $RESOLVED_SOURCE" >&2
    exit 1
    ;;
esac
SOURCE="$RESOLVED_SOURCE"

SITE_KEY="$(sh "$BASE_DIR/scripts/tools/helpers/compute-site-key.sh" "$PROJECT")"

SITE_ROOT="$SHARED_FILES_ROOT/$SITE_KEY"
DEST="$SITE_ROOT/site"            # the path nginx serves (a symlink → a release)
RELEASES_DIR="$SITE_ROOT/releases"

# Progress/diagnostics → stderr; stdout carries only the final served path.
echo "[sync-static-site] Syncing $SOURCE → $DEST" >&2

mkdir -p "$RELEASES_DIR"

# Publish model: each sync builds a *complete* release directory, then repoints
# the `site` symlink at it. nginx therefore only ever follows `site` to a
# fully-copied tree — never a half-written one. Unique per-run names (timestamp
# + PID) avoid collisions between two syncs in the same second.
TS="$(date '+%Y%m%d-%H%M%S')"
_sync_pid=$(printf '%05d' $$)
STAGING="$RELEASES_DIR/.staging-$TS-$_sync_pid"
NEW_RELEASE="$RELEASES_DIR/release-$TS-$_sync_pid"

# Build the release under a hidden staging name first. A symlink that points
# outside this tree is left in place and not published.
rm -rf "$STAGING" "$NEW_RELEASE"
mkdir -p "$STAGING"
cp -a "$SOURCE/." "$STAGING/"
. "$BASE_DIR/scripts/tools/static/publish-lib.sh"
if ! baton_reject_escaping_symlinks "$STAGING"; then
  exit 1
fi
mv "$STAGING" "$NEW_RELEASE"      # rename within the same dir → release appears complete

# Legacy migration: earlier versions made `site` a real directory. A symlink
# repoint can't replace a directory, so move it aside once. Fresh installs and
# every subsequent sync skip this.
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "[sync-static-site] Migrating legacy directory $DEST → symlink layout" >&2
  rm -rf "$DEST"
fi

# Rename a new symlink onto `site`. The target is a fully-built tree.
baton_atomic_symlink "$NEW_RELEASE" "$DEST"

# Prune old releases, keeping the newest 3. Never remove the live target.
# Sort by NAME (release-<timestamp>-<pid>), not mtime: the timestamp prefix
# sorts chronologically and is deterministic even when several releases share a
# second (mtime-based ordering is unstable in that case and can skip a prune).
# Tolerate failures here: the publish above already succeeded and `site` is
# already live, so a stale release that can't be deleted (permission issue,
# stale NFS handle, ...) must not make this script report failure — a caller
# seeing a FAILED exit this late would roll the *backend* back while the new
# frontend stays live (see handle-webhook.sh's static-publish handling).
CURRENT="$(readlink "$DEST" 2>/dev/null || echo "$NEW_RELEASE")"
ls -1d "$RELEASES_DIR"/release-* 2>/dev/null | sort -r | tail -n +4 | while IFS= read -r old; do
  [ "$old" = "$CURRENT" ] && continue
  rm -rf "$old" 2>/dev/null || echo "[sync-static-site] WARNING: could not prune old release: $old" >&2
done || true
# Drop staging dirs older than a day. Never remove the path `site` points at.
baton_sweep_staging "$RELEASES_DIR" "$CURRENT"

echo "[sync-static-site] Sync complete: $DEST → $NEW_RELEASE" >&2

echo "$DEST"
