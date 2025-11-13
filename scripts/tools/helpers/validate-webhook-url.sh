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

# success
exit 0
