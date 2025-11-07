#!/bin/sh
# scripts/tools/commit-config.sh
set -eu

commit_config() {
  tmp_file="$1"
  domain="$2"
  final_file="$CONF_DIR/${domain}.conf"

  # Backup old config
  [ -f "$final_file" ] && mv "$final_file" "$final_file.bak.$(date +%Y%m%d-%H%M%S)"

  mv "$tmp_file" "$final_file"
  echo "Config committed: $final_file"
}