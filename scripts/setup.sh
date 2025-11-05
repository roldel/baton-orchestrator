#!/bin/sh
# scripts/setup.sh - One-time setup for baton-orchestrator
# Run as root or with sudo

set -e  # Exit on any error

# ------------------------------------------------------------------
# 1. Find repo root (fallback to current dir if not in git)
# ------------------------------------------------------------------
if [ -n "$(command -v git)" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BASE_DIR=$(git rev-parse --show-toplevel)
else
    BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fi

echo "Setting up baton-orchestrator from: $BASE_DIR"

# ------------------------------------------------------------------
# 2. Create required directories
# ------------------------------------------------------------------
mkdir -p "$BASE_DIR/orchestrator/data/certs"
mkdir -p "$BASE_DIR/orchestrator/data/certbot-webroot"
mkdir -p "$BASE_DIR/orchestrator/servers-confs"
mkdir -p /shared-files  # Host volume mount point

# ------------------------------------------------------------------
# 3. Create internal Docker network (idempotent)
# ------------------------------------------------------------------
if ! docker network inspect internal_proxy_pass_network >/dev/null 2>&1; then
    echo "Creating Docker network: internal_proxy_pass_network"
    docker network create internal_proxy_pass_network
else
    echo "Docker network 'internal_proxy_pass_network' already exists"
fi

# ------------------------------------------------------------------
# 4. Install inotify-tools (for future webhook reloads)
# ------------------------------------------------------------------
if ! apk info inotify-tools >/dev/null 2>&1; then
    echo "Installing inotify-tools..."
    apk add --no-cache inotify-tools
fi

# ------------------------------------------------------------------
# 5. Install baton CLI symlink
# ------------------------------------------------------------------
BATON_SRC="$BASE_DIR/scripts/baton"
BATON_DEST="/usr/local/bin/baton"

if [ ! -f "$BATON_DEST" ] || [ "$(readlink -f "$BATON_DEST")" != "$BATON_SRC" ]; then
    echo "Installing baton CLI -> $BATON_DEST"
    ln -sf "$BATON_SRC" "$BATON_DEST"
else
    echo "baton CLI already installed"
fi

# Make baton executable
chmod +x "$BATON_SRC"

# ------------------------------------------------------------------
# 6. Final instructions
# ------------------------------------------------------------------
echo ""
echo "Setup complete!"
echo "Use: baton deploy <project> <domain>   # e.g. baton deploy demo-website example.com"
echo "     baton ssl <domain>                # Issue/renew cert"
echo "     baton help                        # Show help"
echo ""
echo "Tip: Add /usr/local/bin to your PATH if not already there."

exit 0