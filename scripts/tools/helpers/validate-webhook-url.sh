#!/usr/bin/env sh
set -eu

WEBHOOK_URL="${1:-${WEBHOOK_URL:-}}"

if [ -z "${WEBHOOK_URL:-}" ]; then
  echo "[validate-webhook-url] ERROR: WEBHOOK_URL is empty" >&2
  exit 1
fi

case "$WEBHOOK_URL" in
  /*) : ;;
  *)
    echo "[validate-webhook-url] ERROR: WEBHOOK_URL must start with '/'" >&2
    exit 1
    ;;
esac

if [ "$WEBHOOK_URL" = "/" ]; then
  echo "[validate-webhook-url] ERROR: WEBHOOK_URL cannot be '/'; it would shadow the entire site." >&2
  exit 1
fi

# webhook-activate.sh substitutes this value unescaped via envsubst into
# `location ${WEBHOOK_URL} { ... }` in webhook.conf. Without restricting the
# character set, a value containing nginx-significant characters ({, }, ;,
# whitespace, quotes, $, newlines, ...) — legitimate shell values, since a
# project's .env can span multiple lines — could inject arbitrary extra
# directives into the shared orchestrator nginx config.
case "$WEBHOOK_URL" in
  *[!A-Za-z0-9._~/-]*)
    echo "[validate-webhook-url] ERROR: WEBHOOK_URL contains characters unsafe for an nginx location block (only letters, digits, '.', '_', '~', '-', '/' are allowed)" >&2
    exit 1
    ;;
esac

# success
exit 0
