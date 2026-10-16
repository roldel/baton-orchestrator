# Phase 8 — a down Docker socket is not an empty site or an empty traffic window.

phase8_stub() {
  _p8s=$1
  shift
  mkdir -p "$(dirname "$_p8s")"
  printf '%s\n' '#!/bin/sh' "$@" > "$_p8s"
  chmod 755 "$_p8s"
}

phase8() {
  _p8=$(mktemp -d)
  mkdir -p "$_p8/projects/phase8app" "$_p8/bin"
  printf '%s\n' 'DOMAIN_NAME=phase8.example' 'STATIC_SITE=no' > "$_p8/projects/phase8app/.env"
  touch "$_p8/projects/phase8app/docker-compose.yml"
  phase8_stub "$_p8/bin/docker" 'exit 0'
  phase8_stub "$_p8/compose-fail" 'exit 1'
  phase8_stub "$_p8/compose-empty" 'exit 0'

  if PATH="$_p8/bin:$PATH" \
      BATON_BASE_DIR="$ROOT" \
      BATON_PROJECTS_ROOT="$_p8/projects" \
      BATON_COMPOSE_CMD="$_p8/compose-fail" \
      sh "$ROOT/scripts/cmd/status.sh" phase8app >"$_p8/status-err.out" 2>"$_p8/status-err.err"
  then
    fail "phase8: status exited 0 when compose ps failed"
  fi
  if ! grep -q 'error' "$_p8/status-err.out"; then
    fail "phase8: status did not report error in the containers column"
  fi
  ok "phase8: failed compose ps is error"

  if ! PATH="$_p8/bin:$PATH" \
      BATON_BASE_DIR="$ROOT" \
      BATON_PROJECTS_ROOT="$_p8/projects" \
      BATON_COMPOSE_CMD="$_p8/compose-empty" \
      sh "$ROOT/scripts/cmd/status.sh" phase8app >"$_p8/status-ok.out" 2>"$_p8/status-ok.err"
  then
    fail "phase8: status failed when compose ps was empty"
  fi
  if ! grep -q 'absent' "$_p8/status-ok.out"; then
    fail "phase8: empty compose ps was not reported as absent"
  fi
  ok "phase8: empty compose ps is absent"

  phase8_stub "$_p8/bin/docker" 'echo socket-down >&2' 'exit 1'
  if PATH="$_p8/bin:$PATH" sh "$ROOT/scripts/tools/analytics/report.sh" \
      >"$_p8/report-err.out" 2>"$_p8/report-err.err"
  then
    fail "phase8: report exited 0 when docker logs failed"
  fi
  if grep -q 'No matching log entries' "$_p8/report-err.out" "$_p8/report-err.err"; then
    fail "phase8: a failed docker logs was reported as an empty window"
  fi
  if ! grep -q 'socket-down' "$_p8/report-err.err"; then
    fail "phase8: report hid docker logs stderr"
  fi
  ok "phase8: failed docker logs exits 1"

  phase8_stub "$_p8/bin/docker" \
    'case "$1" in' \
    '  ps) printf "%s\n" ingress-nginx ;;' \
    'esac' \
    'exit 0'
  if ! PATH="$_p8/bin:$PATH" sh "$ROOT/scripts/tools/analytics/report.sh" \
      >"$_p8/report-ok.out" 2>"$_p8/report-ok.err"
  then
    fail "phase8: report failed on an empty log window"
  fi
  if ! grep -q 'No matching log entries' "$_p8/report-ok.out"; then
    fail "phase8: an empty log window did not say there were no entries"
  fi
  ok "phase8: empty log window still says so"

  rm -rf "$_p8"
}

phase8
