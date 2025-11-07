#!/bin/sh
# Write a temporary "challenge-only" nginx server conf to stdout.
# Usage: write-challenge-conf.sh <domain> [aliases...]
set -eu

domain="${1:-}"; shift || true
[ -n "$domain" ] || { echo "Usage: write-challenge-conf.sh <domain> [aliases...]"; exit 1; }
aliases="$*"

cat <<EOF
# Temporary ACME challenge-only server for $domain
server {
  listen 80;
  listen [::]:80;
  server_name $domain ${aliases:-};

  location /.well-known/acme-challenge/ {
    root /var/www/certbot;
  }

  # No HTTP->HTTPS redirects here; ACME needs plain HTTP.
}
EOF
