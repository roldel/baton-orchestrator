#!/bin/sh
# Sync a static site's built output into the shared-files location nginx
# serves from. Simple wholesale copy (no rsync/delta-checking): copies into a
# sibling temp directory, then atomically renames it into place, so nginx
# never serves an empty or half-copied directory if the copy is interrupted.
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

# shellcheck source=/dev/null
. "$ENV_FILE"

if [ -z "${STATIC_SOURCE_DIR:-}" ]; then
  echo "[sync-static-site] ERROR: STATIC_SOURCE_DIR not set in $ENV_FILE" >&2
  exit 1
fi

SOURCE="$PROJECT_DIR/$STATIC_SOURCE_DIR"
if [ ! -d "$SOURCE" ]; then
  echo "[sync-static-site] ERROR: STATIC_SOURCE_DIR '$STATIC_SOURCE_DIR' not found at $SOURCE" >&2
  exit 1
fi

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
CURRENT="$(readlink "$DEST" 2>/dev/null || echo "$NEW_RELEASE")"
ls -1d "$RELEASES_DIR"/release-* 2>/dev/null | sort -r | tail -n +4 | while IFS= read -r old; do
  [ "$old" = "$CURRENT" ] && continue
  rm -rf "$old"
done
# Sweep any stale staging dirs from interrupted runs.
rm -rf "$RELEASES_DIR"/.staging-* 2>/dev/null || true

echo "[sync-static-site] Sync complete: $DEST → $NEW_RELEASE" >&2

echo "$DEST"
