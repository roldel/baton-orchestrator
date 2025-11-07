# scripts/tools/write-challenge-conf.sh
#!/bin/sh
set -eu

[ $# -ge 1 ] || { echo "Usage: $0 <domain> [alias1 alias2 ...]"; exit 1; }

# All arguments are domains
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