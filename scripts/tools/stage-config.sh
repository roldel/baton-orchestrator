#!/bin/sh
# scripts/tools/stage-config.sh
set -eu

stage_config() {
  content="$1"
  domain="$2"
  tmp_file="$CONF_DIR/.${domain}.conf.tmp.$$"

  printf '%s' "$content" > "$tmp_file"
  echo "$tmp_file"
}