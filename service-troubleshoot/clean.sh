rc-service baton-webhook stop || true

pkill -f watch-webhook.sh || true
pkill -f watch_webhook.sh || true

rc-update del baton-webhook || true

rm -f /run/baton-webhook.pid

rm -f /var/log/baton-webhook.log

rm -f /etc/init.d/baton-webhook
