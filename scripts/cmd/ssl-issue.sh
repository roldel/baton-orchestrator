#!/bin/sh
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via baton"; exit 1; }
. "$BASE_DIR/env-setup.sh"
exec "$SCRIPT_DIR/tools/certbot-issuance.sh" "$@"
