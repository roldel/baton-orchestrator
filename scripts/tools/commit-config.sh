#!/bin/sh
# tools/commit-config.sh
# Atomic move + backup

. "$(dirname "$0")/../env-setup.sh"

commit_config() {
    tmp="$1"
    domain="$2"
    final="$CONF_DIR/${domain}.conf"

    # Backup existing
    if [ -f "$final" ]; then
        backup="$final.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$final" "$backup"
        echo "Backed up → $backup"
    fi

    mv "$tmp" "$final"
    echo "Live → $final"
}
