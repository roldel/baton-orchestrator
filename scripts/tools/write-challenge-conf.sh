#!/bin/sh
# scripts/tools/write-challenge-conf.sh
# Generate challenge-only server block
# Usage: write-challenge-conf.sh domain1 [domain2 ...]

set -eu

[ $# -ge 1 ] || { echo "Usage: $(basename "$0") <domain> [aliases...]"; exit 1; }

domains="$*"

cat <<EOF
# Temporary ACME challenge-only server
server {
  listen 80;
  listen [::]:80;
  server_name $domains;

  location /.well-known/acme-challenge/ {
    root /var/www/certbot;
  }
}
EOF