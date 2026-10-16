# Phase 2 — nginx substitution allowlists and the webhook location.

phase2() {
  . "$ROOT/scripts/tools/helpers/nginx-allowlists.sh"

  if baton_check_app_port '80; } location /x { return 200 x; } #'; then
    fail "phase2: nginx payload accepted as APP_PORT"
  fi
  if baton_check_app_port 0; then
    fail "phase2: APP_PORT 0 accepted"
  fi
  if baton_check_app_port 65536; then
    fail "phase2: APP_PORT 65536 accepted"
  fi
  baton_check_app_port 8000 || fail "phase2: APP_PORT 8000 rejected"
  baton_check_app_port 65535 || fail "phase2: APP_PORT 65535 rejected"
  baton_check_app_port 1 || fail "phase2: APP_PORT 1 rejected"

  if baton_check_service_alias 'app;return'; then
    fail "phase2: service alias payload accepted"
  fi
  if baton_check_service_alias '-app'; then
    fail "phase2: leading-hyphen alias accepted"
  fi
  baton_check_service_alias 'myapp-service' || fail "phase2: myapp-service rejected"
  ok "phase2: port and service alias allowlists"

  baton_check_admin_email 'ops@example.com' || fail "phase2: plain email rejected"
  if baton_check_admin_email 'ops@example.com; }'; then
    fail "phase2: email payload accepted"
  fi
  baton_check_admin_email '' || fail "phase2: empty email rejected"
  baton_check_project_name 'my-app' || fail "phase2: project name rejected"
  if baton_check_project_name '../etc'; then
    fail "phase2: slash project name accepted"
  fi
  ok "phase2: email and project name allowlists"

  _p2_wh="$ROOT/scripts/tools/webhook/webhook.conf"
  if ! grep -q 'location = ${WEBHOOK_URL}' "$_p2_wh"; then
    fail "phase2: webhook template is not an exact location"
  fi
  if ! grep -q 'client_max_body_size 5m;' "$_p2_wh"; then
    fail "phase2: webhook template missing 5m body limit"
  fi
  if grep -q 'client_max_body_size' "$ROOT/orchestrator/nginx/nginx.conf"; then
    fail "phase2: client_max_body_size leaked into nginx.conf"
  fi
  ok "phase2: webhook location is exact and limited to 5m"
}

phase2
