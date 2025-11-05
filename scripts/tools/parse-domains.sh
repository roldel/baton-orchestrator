#!/bin/sh
# tools/parse-domains.sh
# Sets: PARSED_MAIN_DOMAIN, PARSED_ALL_DOMAINS

. "$(dirname "$0")/../env-setup.sh"

parse_domains() {
    file="$1"
    [ ! -f "$file" ] && { echo "File not found: $file" >&2; exit 1; }

    line=$(grep -E '^[[:space:]]*server_name[[:space:]]+' "$file" | head -n1)
    [ -z "$line" ] && { echo "No server_name in $file" >&2; exit 1; }

    domains=$(echo "$line" | \
        sed -E 's/.*server_name[[:space:]]+//; s/[;[:space:]].*$//' | \
        tr ' ' '\n' | grep -v '^$')

    export PARSED_MAIN_DOMAIN=$(echo "$domains" | head -n1)
    export PARSED_ALL_DOMAINS=$(echo "$domains" | tr '\n' ' ' | sed 's/ $//')
}