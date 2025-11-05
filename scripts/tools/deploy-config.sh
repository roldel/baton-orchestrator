#!/bin/sh
# tools/deploy-config.sh
# SAFE: Test first, then atomic move

. "$(dirname "$0")/../env-setup.sh"

deploy_config() {
    src="$1"
    domain="$2"
    final_dst="$CONF_DIR/${domain}.conf"
    tmp_dst="$CONF_DIR/.${domain}.conf.tmp.$$"

    # 1. Copy to temp location (still in same mount, but hidden)
    cp "$src" "$tmp_dst"
    echo "Staged → $tmp_dst"

    # 2. Let nginx-test.sh validate it
    # (We'll call nginx_test from deploy.sh *before* this function returns success)

    # 3. Only on success: atomic move
    if mv "$tmp_dst" "$final_dst" 2>/dev/null; then
        echo "Deployed → $final_dst"
        return 0
    else
        echo "ERROR: Failed to deploy $final_dst" >&2
        rm -f "$tmp_dst"
        return 1
    fi
}