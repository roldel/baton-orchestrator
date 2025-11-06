#!/bin/sh
set -eu

echo "[test_setup_dryrun] Simulating a dry-run of setup.sh with stubbed commands..."

# Resolve project root
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"
SETUP_SCRIPT="$PROJECT_ROOT/scripts/setup.sh"

# Create fake /usr/local/bin/ in tmp
FAKE_ROOT=$(mktemp -d)
trap 'rm -rf "$FAKE_ROOT"' EXIT

# Create dummy paths and override key system folders
export PATH="$FAKE_ROOT/bin:$PATH"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/usr/local/bin"
mkdir -p "$FAKE_ROOT/shared-files"

# Create fake commands to avoid system modifications
for cmd in apk rc-update rc-service docker git envsubst ln chmod; do
  echo "#!/bin/sh" > "$FAKE_ROOT/bin/$cmd"
  echo "echo '[stub] $cmd called'" >> "$FAKE_ROOT/bin/$cmd"
  chmod +x "$FAKE_ROOT/bin/$cmd"
done

# Run the setup script with overridden env
HOME="$FAKE_ROOT" BASE_DIR="$FAKE_ROOT/project" sh "$SETUP_SCRIPT" > /dev/null 2>&1 || {
  echo "[test_setup_dryrun] ❌ Setup script failed unexpectedly"
  exit 1
}

echo "[test_setup_dryrun] ✅ Setup script ran safely with stubbed tools"
exit 0
