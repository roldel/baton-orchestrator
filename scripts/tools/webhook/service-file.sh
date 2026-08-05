#!/sbin/openrc-run
# /etc/init.d/baton-webhook
# Baton Webhook Queue Worker

name="Baton Webhook Watcher"
description="Drains /srv/webhooks/queue for task_*.baton and triggers redeploys"

LOG_FILE="/var/log/baton-webhook.log"

command="/opt/baton-orchestrator/scripts/tools/webhook/watch-webhook.sh"

command_background="yes"
supervisor="supervise-daemon"

pidfile="/run/baton-webhook.pid"

# Logging handled by OpenRC
output_log="${LOG_FILE}"
error_log="${LOG_FILE}"

depend() {
    need docker
    use net
    after docker
}

start_pre() {
    # ensure dirs/files exist with sane perms
    checkpath --directory --mode 0755 /srv/webhooks/queue
    checkpath --directory --mode 0755 /srv/webhooks/processing
    checkpath --directory --mode 0755 /srv/webhooks/processed
    checkpath --directory --mode 0755 /srv/webhooks/failed
    checkpath --file --mode 0644 /var/log/baton-webhook.log
}
