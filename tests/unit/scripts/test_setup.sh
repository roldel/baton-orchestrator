#!/bin/sh
set -eu

echo "[test_setup_dryrun] Simulating a dry-run of setup.sh with stubbed commands..."

# Create isolated fake environment
FAKE_ROOT=$(mktemp -d)
trap 'rm -rf "$FAKE_ROOT"' EXIT

FAKE_PROJECT="$FAKE_ROOT/project"
FAKE_BIN="$FAKE_ROOT/bin"
FAKE_USR_BIN="$FAKE_ROOT/usr/local/bin"
FAKE_SHARED="$FAKE_ROOT/shared-files"
mkdir -p "$FAKE_PROJECT/scripts" "$FAKE_BIN" "$FAKE_USR_BIN" "$FAKE_SHARED"

# Copy the real setup.sh into our fake environment
cp ./scripts/setup.sh "$FAKE_PROJECT/scripts/setup.sh"

# Create a fake baton CLI file to simulate the real one
echo "#!/bin/sh" > "$FAKE_PROJECT/scripts/baton"
chmod +x "$FAKE_PROJECT/scripts/baton"

# Stub out critical system-modifying commands
for cmd in apk rc-update rc-service docker git envsubst ln chmod mkdir docker-compose; do
  echo "#!/bin/sh" > "$FAKE_BIN/$cmd"
  echo "echo \"[stub] $cmd called with: \$@\"" >> "$FAKE_BIN/$cmd"
  chmod +x "$FAKE_BIN/$cmd"
done

# Add fake bin to front of PATH
export PATH="$FAKE_BIN:$PATH"

SETUP_SCRIPT="$FAKE_PROJECT/scripts/setup.sh"

# Run setup.sh in dry-run mode with overrides
if BASE_DIR="$FAKE_PROJECT" BATON_DEST="$FAKE_USR_BIN/baton" sh "$SETUP_SCRIPT" > /dev/null 2>&1; then
  echo "[test_setup_dryrun] ✅ Setup script ran successfully in dry-run mode"

  # Validate that baton symlink was created
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
