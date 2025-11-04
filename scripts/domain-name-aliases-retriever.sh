#!/bin/sh

# Path to your Nginx config file
CONFIG_FILE="nginx.conf"

# Extract server_name line(s) from the config
SERVER_NAMES=$(grep -E '^\s*server_name' "$CONFIG_FILE" | head -n 1 | sed -E 's/^\s*server_name\s+//;s/;\s*$//')

# Split into main domain and aliases
MAIN_DOMAIN=$(echo "$SERVER_NAMES" | awk '{print $1}')
ALIASES=$(echo "$SERVER_NAMES" | awk '{$1=""; print $0}' | sed 's/^ //;s/ $//')

# Output results
echo "Main Domain: $MAIN_DOMAIN"
echo "Aliases: $ALIASES"
