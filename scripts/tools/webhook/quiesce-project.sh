#!/bin/sh
# Cancel queued webhook tasks for one project.
# If a task for that project is already in processing/, exit 1 and change nothing.
#
# Usage: quiesce-project.sh <project>
# BATON_WEBHOOKS_ROOT overrides /srv/webhooks.

set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project>" >&2
  exit 1
fi

PROJECT=$1
WEBHOOKS_ROOT=${BATON_WEBHOOKS_ROOT:-/srv/webhooks}
QUEUE_DIR=$WEBHOOKS_ROOT/queue
PROCESSING_DIR=$WEBHOOKS_ROOT/processing
PROCESSED_DIR=$WEBHOOKS_ROOT/processed

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/queue-lib.sh"

# BATON_QUIESCE_CANCEL_PROCESSING=1 moves a matching processing/ task to
# processed/*.cancelled.<ts>. Unset, a processing task exits 1 and changes nothing.
if [ -d "$PROCESSING_DIR" ]; then
  _q_ts=$(date '+%Y%m%d-%H%M%S')
  for _q_f in "$PROCESSING_DIR"/task_*.baton; do
    [ -f "$_q_f" ] || continue
    if [ "$(task_project "$_q_f")" = "$PROJECT" ]; then
      if [ "${BATON_QUIESCE_CANCEL_PROCESSING:-}" != 1 ]; then
        echo "[quiesce] ERROR: a redeploy of '$PROJECT' is in progress ($_q_f). Rerun when it finishes." >&2
        exit 1
      fi
      mkdir -p "$PROCESSED_DIR"
      _q_base=$(basename -- "$_q_f")
      mv "$_q_f" "$PROCESSED_DIR/${_q_base}.cancelled.${_q_ts}"
    fi
  done
fi

if [ -d "$QUEUE_DIR" ]; then
  mkdir -p "$PROCESSED_DIR"
  _q_ts=$(date '+%Y%m%d-%H%M%S')
  for _q_f in "$QUEUE_DIR"/task_*.baton; do
    [ -f "$_q_f" ] || continue
    if [ "$(task_project "$_q_f")" = "$PROJECT" ]; then
      _q_base=$(basename -- "$_q_f")
      mv "$_q_f" "$PROCESSED_DIR/${_q_base}.cancelled.${_q_ts}"
    fi
  done
fi
