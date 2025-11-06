#!/bin/sh
set -eu

echo "[test_setup_dryrun] Simulating a dry-run of setup.sh with stubbed commands..."

# Create isolated fake environment
FAKE_ROOT=$(mktemp -d)
trap 'rm -rf "$FAKE_ROOT"' EXIT

FAKE_PROJECT="$FAKE_ROOT/project"
FAKE_BIN="$FAKE_ROOT/bin"
FAKE_USR_BIN="$FAKE_ROOT/usr/local/bin"
mkdir -p "$FAKE_PROJECT/scripts" "$FAKE_BIN" "$FAKE_USR_BIN" "$FAKE_ROOT/shared-files"

# Copy the real setup.sh into our fake environment
cp ./scripts/setup.sh "$FAKE_PROJECT/scripts/setup.sh"

# Create a fake baton CLI
echo "#!/bin/sh" > "$FAKE_PROJECT/scripts/baton"
chmod +x "$FAKE_PROJECT/scripts/baton"

# Stub out commands that could touch system state
for cmd in apk rc-update rc-service docker git envsubst ln chmod; do
  echo "#!/bin/sh" > "$FAKE_BIN/$cmd"
  echo "echo \"[stub] $cmd called\"" >> "$FAKE_BIN/$cmd"
  chmod +x "$FAKE_BIN/$cmd"
done

# Make sure our fake commands are used
export PATH="$FAKE_BIN:$PATH"

SETUP_SCRIPT="$FAKE_PROJECT/scripts/setup.sh"

if BASE_DIR="$FAKE_PROJECT" sh "$SETUP_SCRIPT" > /dev/null 2>&1; then
  echo "[test_setup_dryrun] ✅ Setup script ran successfully in dry-run mode"

  # Validate that baton symlink exists
  if [ -L "$FAKE_USR_BIN/baton" ]; then
    echo "[test_setup_dryrun] ✅ Baton symlink created correctly"
    exit 0
  else
    echo "[test_setup_dryrun] ❌ Baton symlink missing"
    exit 1
  fi
else
  echo "[test_setup_dryrun] ❌ Setup script failed unexpectedly"
  exit 1
fi
