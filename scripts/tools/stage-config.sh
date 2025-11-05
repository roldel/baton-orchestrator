#!/bin/sh
# Returns the path to the staged temp file on stdout
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via baton"; exit 1; }
. "$BASE_DIR/env-setup.sh"

stage_config() {
  src="$1"
  domain="$2"
  tmp="$CONF_DIR/.${domain}.conf.tmp.$$"

  cp "$src" "$tmp"
  echo "Staged → $tmp" >&2     # log to stderr
  printf '%s\n' "$tmp"        # return only the path
}
