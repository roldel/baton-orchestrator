# Phase 10 — SERVER_CONF_EXTRA_VARS: names, presence, values, no secret output.

phase10_run() { # $1 env file content; result in _p10_rc, _p10_out, $_p10/err
  printf '%s\n' "$1" > "$_p10/.env"
  _p10_rc=0
  _p10_out=$(baton_server_conf_extra_vars "$_p10/.env" 2> "$_p10/err") || _p10_rc=$?
}

phase10() {
  . "$ROOT/scripts/tools/helpers/load-env-safe.sh"
  . "$ROOT/scripts/tools/helpers/server-conf-extra-vars.sh"
  _p10=$(mktemp -d)

  phase10_run 'DOMAIN_NAME=a.example'
  [ "$_p10_rc" -eq 0 ] && [ -z "$_p10_out" ] || fail "phase10: absent key was not a no-op"
  phase10_run 'SERVER_CONF_EXTRA_VARS='
  [ "$_p10_rc" -eq 0 ] && [ -z "$_p10_out" ] || fail "phase10: empty key was not a no-op"
  ok "phase10: absent or empty declaration adds nothing"

  phase10_run "$(printf '%s\n' 'SERVER_CONF_EXTRA_VARS="A_SECRET, B_TOKEN,A_SECRET"' 'A_SECRET=s3cr3t' 'B_TOKEN=t0k3n')"
  [ "$_p10_rc" -eq 0 ] && [ "$_p10_out" = 'A_SECRET B_TOKEN' ] \
    || fail "phase10: comma/space list parsed as [$_p10_out] rc=$_p10_rc"
  if grep -qE 's3cr3t|t0k3n' "$_p10/err"; then
    fail "phase10: a value reached stderr"
  fi
  ok "phase10: comma and space separated names"

  phase10_run "$(printf '%s\n' 'SERVER_CONF_EXTRA_VARS=bad-name')"
  [ "$_p10_rc" -ne 0 ] && grep -q "'bad-name' is not a valid name" "$_p10/err" \
    || fail "phase10: invalid name accepted"
  phase10_run "$(printf '%s\n' 'SERVER_CONF_EXTRA_VARS=TEMPLATE' 'TEMPLATE=/etc/passwd')"
  [ "$_p10_rc" -ne 0 ] && grep -q 'TEMPLATE is reserved' "$_p10/err" \
    || fail "phase10: reserved name accepted"
  ok "phase10: invalid and reserved names rejected"

  phase10_run "$(printf '%s\n' 'SERVER_CONF_EXTRA_VARS=A_SECRET' 'A_SECRET=')"
  [ "$_p10_rc" -ne 0 ] && grep -q 'A_SECRET is listed in SERVER_CONF_EXTRA_VARS but empty' "$_p10/err" \
    || fail "phase10: empty value accepted"
  printf '%s\n' 'SERVER_CONF_EXTRA_VARS=A_SECRET' > "$_p10/.env"
  _p10_rc=0
  A_SECRET=fromenv baton_server_conf_extra_vars "$_p10/.env" > /dev/null 2> "$_p10/err" || _p10_rc=$?
  [ "$_p10_rc" -ne 0 ] && grep -q 'A_SECRET is listed in SERVER_CONF_EXTRA_VARS but not set' "$_p10/err" \
    || fail "phase10: process environment counted as set in .env"
  ok "phase10: missing or empty values rejected"

  phase10_run "$(printf '%s\n' 'SERVER_CONF_EXTRA_VARS=A_SECRET' "A_SECRET='x; } location / { return 200 pwned; } #'")"
  [ "$_p10_rc" -ne 0 ] && grep -q 'A_SECRET contains characters not allowed' "$_p10/err" \
    || fail "phase10: nginx payload in value accepted"
  if grep -q pwned "$_p10/err"; then
    fail "phase10: rejected value was printed"
  fi
  ok "phase10: unsafe value rejected without printing it"

  if ! grep -q 'baton_server_conf_extra_vars' "$ROOT/scripts/tools/projects/render-server-conf.sh"; then
    fail "phase10: renderer does not use baton_server_conf_extra_vars"
  fi
  if ! grep -q 'validate-env.sh" "$PROJECT" --server-conf-extras' "$ROOT/scripts/cmd/deploy.sh"; then
    fail "phase10: deploy does not validate SERVER_CONF_EXTRA_VARS"
  fi
  ok "phase10: wiring"

  rm -rf "$_p10"
}

phase10
