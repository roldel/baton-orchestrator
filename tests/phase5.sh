# Phase 5 — lifecycle commands finish what they started, or put it back.

phase5_stub() {
  _p5s=$1
  shift
  mkdir -p "$(dirname "$_p5s")"
  printf '%s\n' '#!/bin/sh' "$@" > "$_p5s"
  chmod 755 "$_p5s"
}

phase5() {
  _p5=$(mktemp -d)
  _p5_path=$PATH

  # Quiesce: move this project's queue file, leave the other project's.
  mkdir -p "$_p5/hooks/queue" "$_p5/hooks/processing" "$_p5/hooks/processed"
  printf '%s\n' 'PROJECT=app' 'DOCKER_COMPOSE_RESTART_REQUIRED=NO' > "$_p5/hooks/queue/task_app.baton"
  printf '%s\n' 'PROJECT=other' 'DOCKER_COMPOSE_RESTART_REQUIRED=NO' > "$_p5/hooks/queue/task_other.baton"
  BATON_WEBHOOKS_ROOT="$_p5/hooks" sh "$ROOT/scripts/tools/webhook/quiesce-project.sh" app \
    || fail "phase5: quiesce of a queued task failed"
  if [ -e "$_p5/hooks/queue/task_app.baton" ]; then
    fail "phase5: queued task was not moved"
  fi
  if [ ! -f "$_p5/hooks/queue/task_other.baton" ]; then
    fail "phase5: quiesce moved another project's task"
  fi
  _p5_moved=$(find "$_p5/hooks/processed" -name 'task_app.baton.cancelled.*' | wc -l | tr -d ' ')
  if [ "$_p5_moved" -ne 1 ]; then
    fail "phase5: expected one cancelled task, found $_p5_moved"
  fi
  printf '%s\n' 'PROJECT=app' > "$_p5/hooks/processing/task_busy.baton"
  if BATON_WEBHOOKS_ROOT="$_p5/hooks" sh "$ROOT/scripts/tools/webhook/quiesce-project.sh" app; then
    fail "phase5: quiesce succeeded while a task was in processing"
  fi
  ok "phase5: quiesce"

  # Resolve: a later illegal line is a parse error, not auto-detect.
  mkdir -p "$_p5/proj"
  printf '%s\n' 'DOCKER_COMPOSE_FILES=compose.prod.yml' 'this is not a valid line' > "$_p5/proj/.env"
  touch "$_p5/proj/compose.prod.yml"
  if BATON_BASE_DIR="$ROOT" sh "$ROOT/scripts/tools/helpers/resolve-compose-files.sh" "$_p5/proj" > "$_p5/resolve.out"; then
    fail "phase5: resolve-compose accepted a broken .env"
  fi
  if [ -s "$_p5/resolve.out" ]; then
    fail "phase5: resolve-compose printed a path after a parse error"
  fi
  ok "phase5: compose file parse errors fail closed"

  # Activate twice, then a failing envsubst that must not create the target.
  . "$ROOT/scripts/tools/webhook/snippet-lib.sh"
  phase5_stub "$_p5/bin/envsubst" 'cat'
  phase5_stub "$_p5/bin/nginx-ok" 'exit 0'
  phase5_stub "$_p5/bin/reload-ok" 'exit 0'
  printf '%s\n' 'webhook ${WEBHOOK_URL}' > "$_p5/template"
  export DOMAIN_NAME=example.com WEBHOOK_URL=/hook
  PATH="$_p5/bin:$PATH"
  baton_install_webhook_snippet "$_p5/template" "$_p5/webhooks.d/example.com-webhook.conf" \
    "$_p5/bin/nginx-ok" "$_p5/bin/reload-ok" || fail "phase5: first activate failed"
  baton_install_webhook_snippet "$_p5/template" "$_p5/webhooks.d/example.com-webhook.conf" \
    "$_p5/bin/nginx-ok" "$_p5/bin/reload-ok" || fail "phase5: second activate failed"
  ok "phase5: repeated activate succeeds"

  phase5_stub "$_p5/bin/envsubst" 'exit 1'
  if baton_install_webhook_snippet "$_p5/template" "$_p5/missing.conf" \
      "$_p5/bin/nginx-ok" "$_p5/bin/reload-ok"; then
    fail "phase5: failing envsubst was treated as success"
  fi
  if [ -e "$_p5/missing.conf" ]; then
    fail "phase5: failing envsubst created the target"
  fi
  ok "phase5: failed envsubst leaves no snippet"

  # Stand-down: site-key failure happens before any container stop.
  mkdir -p "$_p5/projects/demo"
  printf '%s\n' 'DOMAIN_NAME=example.com' 'STATIC_SITE=no' > "$_p5/projects/demo/.env"
  phase5_stub "$_p5/site-key.sh" 'echo "[site-key] boom" >&2' 'exit 1'
  phase5_stub "$_p5/compose-stop.sh" "echo stopped > '$_p5/stopped'" 'exit 0'
  mkdir -p "$_p5/empty-hooks/queue" "$_p5/empty-hooks/processing" "$_p5/empty-hooks/processed"
  if BATON_BASE_DIR="$ROOT" \
      BATON_PROJECTS_ROOT="$_p5/projects" \
      BATON_WEBHOOKS_ROOT="$_p5/empty-hooks" \
      BATON_SITE_KEY_HELPER="$_p5/site-key.sh" \
      BATON_COMPOSE_CMD="$_p5/compose-stop.sh" \
      sh "$ROOT/scripts/cmd/stand-down.sh" demo; then
    fail "phase5: stand-down succeeded after site-key failure"
  fi
  if [ -e "$_p5/stopped" ]; then
    fail "phase5: stand-down stopped containers after site-key failure"
  fi
  ok "phase5: stand-down stops before containers when site-key fails"

  PATH=$_p5_path
  rm -rf "$_p5"
  unset DOMAIN_NAME WEBHOOK_URL
}

phase5
