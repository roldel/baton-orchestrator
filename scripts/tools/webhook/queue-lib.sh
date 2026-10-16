#!/bin/sh
# Queue helpers shared by the webhook worker and quiesce.
# Callers set QUEUE_DIR, PROCESSED_DIR, and PATTERN, and define log().

# First value of KEY= in a task file. No quote stripping and no sourcing.
task_field() {
  _tf_file=$1
  _tf_key=$2
  _tf_val=
  while IFS= read -r _tf_line || [ -n "$_tf_line" ]; do
    case $_tf_line in
      "$_tf_key"=*)
        _tf_val=${_tf_line#"$_tf_key"=}
        break
        ;;
    esac
  done < "$_tf_file"
  printf '%s' "$_tf_val"
}

task_project() {
  task_field "$1" PROJECT
}

# True when DOCKER_COMPOSE_RESTART_REQUIRED is YES in any case.
task_restart_yes() {
  _try=$(task_field "$1" DOCKER_COMPOSE_RESTART_REQUIRED)
  _try=$(printf '%s' "$_try" | tr '[:lower:]' '[:upper:]')
  [ "$_try" = YES ]
}

# Rewrite the restart line of a queue file to YES via a temp file in queue/.
baton_force_restart_yes() {
  _bfy=$1
  _bfy_dir=$(dirname -- "$_bfy")
  _bfy_tmp=$(mktemp "$_bfy_dir/.yes.XXXXXX") || return 1
  _bfy_found=0
  while IFS= read -r _bfy_line || [ -n "$_bfy_line" ]; do
    case $_bfy_line in
      DOCKER_COMPOSE_RESTART_REQUIRED=*)
        printf '%s\n' 'DOCKER_COMPOSE_RESTART_REQUIRED=YES'
        _bfy_found=1
        ;;
      *)
        printf '%s\n' "$_bfy_line"
        ;;
    esac
  done < "$_bfy" > "$_bfy_tmp"
  if [ "$_bfy_found" -eq 0 ]; then
    printf '%s\n' 'DOCKER_COMPOSE_RESTART_REQUIRED=YES' >> "$_bfy_tmp"
  fi
  mv -f "$_bfy_tmp" "$_bfy"
}

# Collapse pending tasks for the same project into the newest one.
# If any task in the group asked for a compose restart, the survivor says YES.
coalesce_queue() {
  _list="$(find "$QUEUE_DIR" -maxdepth 1 -type f -name "$PATTERN" 2>/dev/null | sort)"
  [ -n "$_list" ] || return 0

  _count=0
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    _count=$((_count + 1))
  done <<EOF
$_list
EOF
  [ "$_count" -ge 2 ] || return 0

  _windir="$(mktemp -d /tmp/baton-coalesce.XXXXXX)" || return 0
  TAB="$(printf '\t')"

  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    _p="$(task_project "$f")"
    [ -n "$_p" ] || _p="__unknown__:$(basename -- "$f")"
    _key="$(printf '%s' "$_p" | cksum | awk '{print $1}')"
    _yes=NO
    if task_restart_yes "$f"; then
      _yes=YES
    fi
    if [ -f "$_windir/$_key" ]; then
      _prev="$(cat "$_windir/$_key")"
      _prev_rest=${_prev#*"$TAB"}
      _prev_yes=${_prev_rest#*"$TAB"}
      _prev_project=${_prev%%"$TAB"*}
      if [ "$_prev_project" = "$_p" ] && [ "$_prev_yes" = YES ]; then
        _yes=YES
      fi
    fi
    printf '%s\t%s\t%s\n' "$_p" "$f" "$_yes" > "$_windir/$_key"
  done <<EOF
$_list
EOF

  for _rec in "$_windir"/*; do
    [ -f "$_rec" ] || continue
    _line="$(cat "$_rec")"
    _rest=${_line#*"$TAB"}
    _winner=${_rest%%"$TAB"*}
    _yes=${_rest#*"$TAB"}
    if [ "$_yes" = YES ] && [ -f "$_winner" ]; then
      baton_force_restart_yes "$_winner"
    fi
  done

  _dropped=0
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    _p="$(task_project "$f")"
    [ -n "$_p" ] || _p="__unknown__:$(basename -- "$f")"
    _key="$(printf '%s' "$_p" | cksum | awk '{print $1}')"
    _winner_line=""
    if [ -f "$_windir/$_key" ]; then
      _winner_line="$(cat "$_windir/$_key")"
    fi
    _winner_project="${_winner_line%%"$TAB"*}"
    _winner_rest=${_winner_line#*"$TAB"}
    _winner="${_winner_rest%%"$TAB"*}"
    if [ "$_winner_project" = "$_p" ] && [ -n "$_winner" ] && [ "$f" != "$_winner" ]; then
      _base="$(basename -- "$f")"
      _dest="$PROCESSED_DIR/${_base}.coalesced.$(date +%s).$$"
      if mv "$f" "$_dest" 2>/dev/null; then
        _dropped=$((_dropped + 1))
        log "Coalesced (dropped older duplicate): $_base"
      fi
    fi
  done <<EOF
$_list
EOF

  rm -rf "$_windir"

  if [ "$_dropped" -gt 0 ]; then
    log "Coalesced $_dropped older task(s); keeping newest per project"
  fi
}
