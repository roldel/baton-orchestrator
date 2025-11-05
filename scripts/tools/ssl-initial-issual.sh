docker compose exec certbot certbot certonly \
  --agree-tos --email admin@example.com \
  --webroot -w /var/www/certbot \
  -d example.com -d www.example.com
