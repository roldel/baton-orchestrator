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

# Read in an isolated subshell, not sourced into this shell directly: a
# malformed .env would otherwise abort under set -eu, and a project .env
# that happens to define BASE_DIR (or any other variable this script itself
# relies on, e.g. for the compute-site-key.sh call below) would silently
# clobber it, letting a project's .env redirect which script gets executed
# with the orchestrator's privileges.
STATIC_SOURCE_DIR="$(
  set +eu
  # shellcheck source=/dev/null
  . "$ENV_FILE" >/dev/null 2>&1
  printf '%s' "${STATIC_SOURCE_DIR:-}"
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

# Resolve symlinks/".." and confirm the result is still inside PROJECT_DIR.
# STATIC_SOURCE_DIR comes from the project's own .env; without this check a
# value like "../../../../etc" would publish files from outside the
# project's own directory to the public internet via nginx.
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
STAGING="$RELEASES_DIR/.staging-$TS-$$"
NEW_RELEASE="$RELEASES_DIR/release-$TS-$$"

# Build the release under a hidden staging name first; if the copy dies partway,
# the half-tree is a dotfile that is never linked and gets cleaned next run.
rm -rf "$STAGING" "$NEW_RELEASE"
mkdir -p "$STAGING"
cp -a "$SOURCE/." "$STAGING/"
mv "$STAGING" "$NEW_RELEASE"      # rename within the same dir → release appears complete

# Legacy migration: earlier versions made `site` a real directory. A symlink
# repoint can't replace a directory, so move it aside once. Fresh installs and
# every subsequent sync skip this.
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "[sync-static-site] Migrating legacy directory $DEST → symlink layout" >&2
  rm -rf "$DEST"
fi

# Repoint `site` at the new release. `ln -sfn` swaps the symlink in place; the
# window is a bare unlink+symlink (no data movement), and the target is always a
# fully-built tree.
ln -sfn "$NEW_RELEASE" "$DEST"

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
# Sweep any stale staging dirs from interrupted runs.
rm -rf "$RELEASES_DIR"/.staging-* 2>/dev/null || true

echo "[sync-static-site] Sync complete: $DEST → $NEW_RELEASE" >&2

echo "$DEST"
