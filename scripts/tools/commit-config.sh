#!/bin/sh
set -eu
[ -n "${BASE_DIR:-}" ] || { echo "Run via baton"; exit 1; }
. "$BASE_DIR/env-setup.sh"

commit_config() {
  tmp="$1"
  domain="$2"
  final="$CONF_DIR/${domain}.conf"

  if [ -f "$final" ]; then
    backup="$final.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$final" "$backup"
    echo "Backed up → $backup"
  fi

  mv "$tmp" "$final"
  echo "Live → $final"
}
