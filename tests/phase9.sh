# Phase 9 — rendered nginx and compose scans, stand-down without a compose
# file, and status output order.

phase9_stub() {
  _p9s=$1
  shift
  mkdir -p "$(dirname "$_p9s")"
  printf '%s\n' '#!/bin/sh' "$@" > "$_p9s"
  chmod 755 "$_p9s"
}

phase9_subst() {
  sed \
    -e 's|\${DOMAIN_NAME}|app.example|g' \
    -e 's|\${DOMAIN_ALIASES}|www.app.example|g' \
    -e 's|\${DOCKER_NETWORK_SERVICE_ALIAS}|app|g' \
    -e 's|\${APP_PORT}|8000|g' \
    -e 's|\${SITE_KEY}|app.example|g' \
    "$1"
}

phase9() {
  . "$ROOT/scripts/tools/helpers/nginx-conf-allow.sh"
  . "$ROOT/scripts/tools/helpers/compose-guard.sh"
  . "$ROOT/scripts/tools/webhook/task-lib.sh"

  _p9=$(mktemp -d)

  phase9_subst "$ROOT/example-project/server.conf" > "$_p9/dynamic.conf"
  baton_check_rendered_conf "$_p9/dynamic.conf" app.example "www.app.example" \
    app.example app 8000 || fail "phase9: dynamic example server.conf was rejected"
  phase9_subst "$ROOT/example-project-static/server.conf" > "$_p9/static.conf"
  baton_check_rendered_conf "$_p9/static.conf" app.example "www.app.example" \
    app.example "" "" || fail "phase9: static example server.conf was rejected"
  ok "phase9: example server.conf passes"

  printf '%s\n' \
    'server {' \
    '    server_name app.example;' \
    '    listen 80;' \
    '    root /var/www/acme-challenge;' \
    '    alias /etc/passwd;' \
    '}' > "$_p9/alias-bad.conf"
  if baton_check_rendered_conf "$_p9/alias-bad.conf" app.example "" app.example app 8000; then
    fail "phase9: alias /etc/passwd was accepted"
  fi
  printf '%s\n' 'server_name app.example evil.example;' > "$_p9/name-bad.conf"
  if baton_check_rendered_conf "$_p9/name-bad.conf" app.example "" app.example app 8000; then
    fail "phase9: foreign server_name was accepted"
  fi
  printf '%s\n' 'include /etc/nginx/nginx.conf;' > "$_p9/inc-bad.conf"
  if baton_check_rendered_conf "$_p9/inc-bad.conf" app.example "" app.example app 8000; then
    fail "phase9: include of nginx.conf was accepted"
  fi
  printf '%s\n' 'proxy_pass http://evil:80;' > "$_p9/proxy-bad.conf"
  if baton_check_rendered_conf "$_p9/proxy-bad.conf" app.example "" app.example app 8000; then
    fail "phase9: proxy_pass to another upstream was accepted"
  fi
  printf '%s\n' 'listen 80 default_server;' > "$_p9/def-bad.conf"
  if baton_check_rendered_conf "$_p9/def-bad.conf" app.example "" app.example app 8000; then
    fail "phase9: default_server was accepted"
  fi
  printf '%s\n' 'proxy_pass http://app:8000;' > "$_p9/proxy-static.conf"
  if baton_check_rendered_conf "$_p9/proxy-static.conf" app.example "" app.example "" ""; then
    fail "phase9: proxy_pass was accepted without an upstream"
  fi
  printf '%s\n' \
    'proxy_pass http://app:8000;' \
    'include /etc/nginx/webhooks.d/app.example-*.conf;' \
    > "$_p9/proxy-ok.conf"
  baton_check_rendered_conf "$_p9/proxy-ok.conf" app.example "" app.example app 8000 \
    || fail "phase9: proxy_pass http://app:8000 was rejected"
  ok "phase9: nginx scan rejects host escapes"

  mkdir -p "$_p9/proj/data"
  printf '%s\n' \
    'services:' \
    '  web:' \
    '    volumes:' \
    '      - type: bind' \
    "        source: $_p9/proj/data" \
    '        target: /data' \
    '      - type: volume' \
    '        source: named' \
    '        target: /vol' \
    '      - ./rel:/data' \
    > "$_p9/compose-ok.yml"
  baton_compose_config_allowed "$_p9/compose-ok.yml" "$_p9/proj" \
    || fail "phase9: project bind was rejected"
  printf '%s\n' \
    'services:' \
    '  web:' \
    '    volumes:' \
    '      - type: bind' \
    '        source: /etc' \
    '        target: /mnt' \
    > "$_p9/compose-etc.yml"
  if baton_compose_config_allowed "$_p9/compose-etc.yml" "$_p9/proj"; then
    fail "phase9: bind of /etc was accepted"
  fi
  printf '%s\n' \
    'services:' \
    '  web:' \
    '    volumes:' \
    '      - type: bind' \
    '        source: /srv/shared-files/app.example/static' \
    '        target: /static_files' \
    '      - /srv/shared-files/app.example/media:/media:rw' \
    > "$_p9/compose-shared.yml"
  baton_compose_config_allowed "$_p9/compose-shared.yml" "$_p9/proj" \
    /srv/shared-files/app.example \
    || fail "phase9: shared-files bind was rejected"
  printf '%s\n' \
    'services:' \
    '  web:' \
    '    volumes:' \
    '      - type: bind' \
    '        source: /srv/shared-files/other.example/static' \
    '        target: /static_files' \
    > "$_p9/compose-shared-other.yml"
  if baton_compose_config_allowed "$_p9/compose-shared-other.yml" "$_p9/proj" \
      /srv/shared-files/app.example; then
    fail "phase9: another site's shared-files bind was accepted"
  fi
  printf '%s\n' \
    'services:' \
    '  web:' \
    '    volumes:' \
    '      - type: bind' \
    '        source: /srv/shared-files/app.example-evil/static' \
    '        target: /static_files' \
    > "$_p9/compose-shared-prefix.yml"
  if baton_compose_config_allowed "$_p9/compose-shared-prefix.yml" "$_p9/proj" \
      /srv/shared-files/app.example; then
    fail "phase9: shared-files prefix bind was accepted"
  fi
  mkdir -p "$_p9/siteproj"
  printf '%s\n' 'DOMAIN_NAME=app.example' > "$_p9/siteproj/.env"
  _p9_shared=$(baton_compose_shared_dir "$_p9/siteproj" \
    "$ROOT/scripts/tools/helpers") || _p9_shared=""
  if [ "$_p9_shared" != /srv/shared-files/app.example ]; then
    fail "phase9: shared dir resolved to '${_p9_shared:-}'"
  fi
  printf '%s\n' 'DOMAIN_NAME=../etc' > "$_p9/siteproj/.env"
  _p9_shared=$(baton_compose_shared_dir "$_p9/siteproj" \
    "$ROOT/scripts/tools/helpers") || _p9_shared=""
  if [ -n "$_p9_shared" ]; then
    fail "phase9: unsafe DOMAIN_NAME resolved a shared dir"
  fi
  printf '%s\n' \
    'services:' \
    '  web:' \
    '    volumes:' \
    '      - /var/run/docker.sock:/var/run/docker.sock' \
    > "$_p9/compose-sock.yml"
  if baton_compose_config_allowed "$_p9/compose-sock.yml" "$_p9/proj"; then
    fail "phase9: docker.sock was accepted"
  fi
  printf '%s\n' 'services:' '  web:' '    privileged: true' > "$_p9/compose-priv.yml"
  if baton_compose_config_allowed "$_p9/compose-priv.yml" "$_p9/proj"; then
    fail "phase9: privileged: true was accepted"
  fi
  printf '%s\n' 'services:' '  web:' '    network_mode: host' > "$_p9/compose-host.yml"
  if baton_compose_config_allowed "$_p9/compose-host.yml" "$_p9/proj"; then
    fail "phase9: host network was accepted"
  fi
  printf '%s\n' 'services:' '  web:' '    cap_add:' '      - SYS_ADMIN' > "$_p9/compose-cap.yml"
  if baton_compose_config_allowed "$_p9/compose-cap.yml" "$_p9/proj"; then
    fail "phase9: SYS_ADMIN was accepted"
  fi
  ok "phase9: compose scan"

  mkdir -p "$_p9/repo"
  printf '%s\n' '#!/bin/sh' "touch '$_p9/ran'" > "$_p9/repo/build.sh"
  chmod 755 "$_p9/repo/build.sh"
  if baton_run_as_webhook_user "$_p9/repo/build.sh" "$_p9/repo"; then
    fail "phase9: project script ran without uid 65532"
  fi
  if [ -e "$_p9/ran" ]; then
    fail "phase9: project script ran as the current user"
  fi
  ok "phase9: project scripts do not run as root"

  mkdir -p "$_p9/hooks/queue" "$_p9/hooks/processing" "$_p9/hooks/processed"
  printf '%s\n' 'PROJECT=app' > "$_p9/hooks/processing/task_busy.baton"
  printf '%s\n' 'PROJECT=other' > "$_p9/hooks/processing/task_other.baton"
  printf '%s\n' 'PROJECT=app' > "$_p9/hooks/queue/task_app.baton"
  BATON_WEBHOOKS_ROOT="$_p9/hooks" BATON_QUIESCE_CANCEL_PROCESSING=1 \
    sh "$ROOT/scripts/tools/webhook/quiesce-project.sh" app \
    || fail "phase9: cancel-processing quiesce failed"
  if [ -e "$_p9/hooks/processing/task_busy.baton" ]; then
    fail "phase9: processing task was not cancelled"
  fi
  if [ ! -e "$_p9/hooks/processing/task_other.baton" ]; then
    fail "phase9: another project's processing task was cancelled"
  fi
  _p9_cancelled=$(find "$_p9/hooks/processed" -name 'task_busy.baton.cancelled.*' | wc -l | tr -d ' ')
  if [ "$_p9_cancelled" -ne 1 ]; then
    fail "phase9: expected one cancelled processing task, found $_p9_cancelled"
  fi
  ok "phase9: stand-down can cancel a processing task"

  mkdir -p "$_p9/projects/nocompose" "$_p9/empty-hooks/queue" \
    "$_p9/empty-hooks/processing" "$_p9/empty-hooks/processed"
  printf '%s\n' 'DOMAIN_NAME=nocompose.example' 'STATIC_SITE=no' \
    > "$_p9/projects/nocompose/.env"
  phase9_stub "$_p9/nginx-test" "touch '$_p9/nginx-tested'" 'exit 0'
  phase9_stub "$_p9/nginx-reload" 'exit 0'
  phase9_stub "$_p9/compose-down" "touch '$_p9/compose-called'" 'exit 0'
  if ! BATON_BASE_DIR="$ROOT" \
      BATON_PROJECTS_ROOT="$_p9/projects" \
      BATON_WEBHOOKS_ROOT="$_p9/empty-hooks" \
      BATON_LOCK_FILE="$_p9/lock" \
      BATON_COMPOSE_CMD="$_p9/compose-down" \
      BATON_NGINX_TEST="$_p9/nginx-test" \
      BATON_NGINX_RELOAD="$_p9/nginx-reload" \
      sh "$ROOT/scripts/cmd/stand-down.sh" nocompose \
      >"$_p9/sd.out" 2>"$_p9/sd.err"
  then
    cat "$_p9/sd.out" "$_p9/sd.err" >&2
    fail "phase9: stand-down with no compose file failed"
  fi
  if [ ! -e "$_p9/nginx-tested" ]; then
    fail "phase9: stand-down did not test nginx"
  fi
  if [ -e "$_p9/compose-called" ]; then
    fail "phase9: stand-down ran compose without a compose file"
  fi
  rm -rf "$ROOT/tmp/nginx-backups"
  rmdir "$ROOT/tmp" 2>/dev/null || true
  ok "phase9: stand-down continues when no compose file exists"

  mkdir -p "$_p9/projects/webapp" "$_p9/bin"
  printf '%s\n' 'DOMAIN_NAME=webapp.example' 'STATIC_SITE=no' \
    > "$_p9/projects/webapp/.env"
  touch "$_p9/projects/webapp/docker-compose.yml"
  phase9_stub "$_p9/bin/docker" 'exit 0'
  phase9_stub "$_p9/compose-banner" \
    'echo "[compose-cmd] dir=should-not-lead files: x" >&2' \
    'echo webapp-container' \
    'exit 0'
  if ! PATH="$_p9/bin:$PATH" \
      BATON_BASE_DIR="$ROOT" \
      BATON_PROJECTS_ROOT="$_p9/projects" \
      BATON_COMPOSE_CMD="$_p9/compose-banner" \
      sh "$ROOT/scripts/cmd/status.sh" webapp \
      >"$_p9/status-ok.out" 2>"$_p9/status-ok.err"
  then
    cat "$_p9/status-ok.out" "$_p9/status-ok.err" >&2
    fail "phase9: status failed on a successful compose ps"
  fi
  if grep -q '\[compose-cmd\]' "$_p9/status-ok.out" "$_p9/status-ok.err"; then
    fail "phase9: compose-cmd banner leaked into status"
  fi
  if grep -q 'compose:' "$_p9/status-ok.out"; then
    cat "$_p9/status-ok.out" >&2
    fail "phase9: status printed a compose file line"
  fi
  if ! grep -q 'webapp' "$_p9/status-ok.out"; then
    fail "phase9: status did not print the project row"
  fi
  ok "phase9: status table has no compose file line"

  phase9_stub "$_p9/compose-fail" \
    'echo "[compose-cmd] dir=boom files: x" >&2' \
    'echo "ps failed" >&2' \
    'exit 1'
  if PATH="$_p9/bin:$PATH" \
      BATON_BASE_DIR="$ROOT" \
      BATON_PROJECTS_ROOT="$_p9/projects" \
      BATON_COMPOSE_CMD="$_p9/compose-fail" \
      sh "$ROOT/scripts/cmd/status.sh" webapp \
      >"$_p9/status-bad.out" 2>"$_p9/status-bad.err"
  then
    fail "phase9: status exited 0 when compose ps failed"
  fi
  if ! awk '
    /webapp/ && !row { row = NR }
    /\[compose-cmd\]/ && !banner { banner = NR }
    END { exit !(row && banner && banner > row) }
  ' "$_p9/status-bad.out"; then
    cat "$_p9/status-bad.out" >&2
    fail "phase9: compose-cmd error was not printed after the project row"
  fi
  _p9_banners=$(grep -c '\[compose-cmd\]' "$_p9/status-bad.out" || true)
  if [ "$_p9_banners" -ne 1 ]; then
    cat "$_p9/status-bad.out" >&2
    fail "phase9: compose error was printed ${_p9_banners:-0} times"
  fi
  ok "phase9: status shows compose errors under the project"

  if ! grep -q 'up -d --build nginx webhook' "$ROOT/scripts/setup.sh"; then
    fail "phase9: setup.sh does not build the webhook image"
  fi
  for _p9_f in "$ROOT/scripts/cmd/stand-down.sh" "$ROOT/scripts/cmd/deploy.sh" \
      "$ROOT/scripts/cmd/respawn.sh"; do
    if ! grep -q 'baton_hold_webhook_lock' "$_p9_f"; then
      fail "phase9: $_p9_f does not hold the webhook lock"
    fi
  done
  for _p9_f in "$ROOT/scripts/setup.sh" "$ROOT/scripts/tools/webhook/service-file.sh" \
      "$ROOT/scripts/cmd/deploy.sh"; do
    if ! grep -q 'grant-webhook-read.sh' "$_p9_f"; then
      fail "phase9: $_p9_f does not grant .env group read"
    fi
  done
  if ! grep -q 'baton_compose_config_allowed' "$ROOT/scripts/tools/helpers/compose-cmd.sh"; then
    fail "phase9: compose-cmd does not scan the compose config"
  fi
  if ! grep -q 'baton_compose_shared_dir' "$ROOT/scripts/tools/helpers/compose-cmd.sh"; then
    fail "phase9: compose-cmd does not allow the project shared-files directory"
  fi
  if ! grep -q 'baton_check_rendered_conf' "$ROOT/scripts/tools/projects/install-server-conf.sh"; then
    fail "phase9: install-server-conf does not scan the rendered file"
  fi
  if ! grep -q 'webhook-activate.sh' "$ROOT/scripts/cmd/respawn.sh"; then
    fail "phase9: respawn does not refresh the webhook"
  fi
  if grep -q 'nothing to restore' "$ROOT/scripts/cmd/respawn.sh"; then
    fail "phase9: respawn still skips an existing webhook snippet"
  fi
  ok "phase9: wiring"

  rm -rf "$_p9"
  unset BATON_WEBHOOKS_ROOT BATON_QUIESCE_CANCEL_PROCESSING
}

phase9
