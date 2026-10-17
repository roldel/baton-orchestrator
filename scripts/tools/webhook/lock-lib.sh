#!/bin/sh
# Hold the webhook lock for this process.
# Call this before shift and pass "$@".
# A child inherits BATON_LOCK_HELD, so respawn's stand-down and deploy do
# not take the lock a second time.
#
# util-linux flock accepts -o and -w. BusyBox flock (Alpine) accepts neither:
# it can lock an already-open fd, which this process keeps across re-exec.

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

  # -o closes the lock fd in the child, so killing flock releases the lock.
  # -w 60 gives up if another holder keeps it.
  if [ "${BATON_FLOCK_IMPL:-}" != busybox ] && flock -o /dev/null true >/dev/null 2>&1; then
    export BATON_LOCK_HELD=1
    exec flock -o -w 60 "$_bhw_lock" "$0" "$@"
  fi

  exec 9>>"$_bhw_lock" || {
    echo "[lock] ERROR: cannot open $_bhw_lock" >&2
    exit 1
  }
  _bhw_n=0
  while ! flock -n 9; do
    _bhw_n=$((_bhw_n + 1))
    if [ "$_bhw_n" -ge 60 ]; then
      echo "[lock] ERROR: timed out waiting for $_bhw_lock" >&2
      exit 1
    fi
    sleep 1
  done
  export BATON_LOCK_HELD=1
  exec "$0" "$@"
}
