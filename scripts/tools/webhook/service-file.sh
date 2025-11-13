#!/sbin/openrc-run
# /etc/init.d/baton-webhook
# Baton Webhook Watcher Service (OpenRC)

name="Baton Webhook Watcher"
description="Monitors /srv/webhooks/signals/ for task_*.baton and triggers redeploys"

command="/opt/baton-orchestrator/scripts/tools/webhook/watch_webhook.sh"
command_background="yes"
pidfile="/run/baton-webhook.pid"
output_log="/var/log/baton-webhook.log"
error_log="/var/log/baton-webhook.log"

depend() {
    need docker
    use net
    after docker
}

start_pre() {
    # ensure dirs/files exist with sane perms
    checkpath --directory --mode 0755 /srv/webhooks/signals
    checkpath --file --mode 0644 /var/log/baton-webhook.log
}
