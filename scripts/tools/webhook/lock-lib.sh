#!/bin/sh
# Hold the webhook flock for this process.
# Re-execs "$0" with the arguments it was given unless BATON_LOCK_HELD=1.
# Call it before shift and pass "$@".
# A child inherits BATON_LOCK_HELD, so respawn's stand-down and deploy do
# not take the lock a second time.

baton_hold_webhook_lock() {
  if [ "${BATON_LOCK_HELD:-}" = 1 ]; then
    return 0
  fi
  if [ -n "${BATON_LOCK_FILE:-}" ]; then
    _bhw_lock=$BATON_LOCK_FILE
  elif [ -w /run ] 2>/dev/null; then
    _bhw_lock=/run/baton-webhook.lock
  else
    _bhw_lock=/tmp/baton-webhook.lock
  fi
  export BATON_LOCK_HELD=1
  # -o closes the lock fd in the child. The kernel drops the lock when this
  # flock parent exits, including on SIGKILL.
  exec flock -o -w 60 "$_bhw_lock" "$0" "$@"
}
