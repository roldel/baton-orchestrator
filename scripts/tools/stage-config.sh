#!/bin/sh
# tools/stage-config.sh
# Returns path to temp file

. "$(dirname "$0")/../env-setup.sh"

stage_config() {
    src="$1"
    domain="$2"
    tmp="$CONF_DIR/.${domain}.conf.tmp.$$"

    cp "$src" "$tmp"
    echo "Staged → $tmp"
    echo "$tmp"  # Output path for caller
}