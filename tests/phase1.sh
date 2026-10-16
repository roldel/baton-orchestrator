# Phase 1 — .env cannot own the orchestrator process.

phase1() {
  _p1_dir=$(mktemp -d)
  _p1_path=$PATH

  . "$ROOT/scripts/tools/helpers/load-env-safe.sh"

  printf '%s\n' 'PATH=/tmp/evil' > "$_p1_dir/path.env"
  if load_env_safe "$_p1_dir/path.env"; then
    fail "phase1: PATH= in .env was accepted"
  fi
  if [ "$PATH" != "$_p1_path" ]; then
    fail "phase1: PATH changed to $PATH"
  fi
  ok "phase1: reserved PATH key rejected"

  printf '%s\n' "GIT_CONFIG_KEY_0=core.sshCommand" > "$_p1_dir/git.env"
  if load_env_safe "$_p1_dir/git.env"; then
    fail "phase1: GIT_CONFIG_KEY_* was accepted"
  fi
  ok "phase1: GIT_CONFIG_KEY_* rejected"

  printf '%s\n' "APP_PORT='80; echo PWNED'" > "$_p1_dir/port.env"
  load_env_safe "$_p1_dir/port.env" || fail "phase1: quoted APP_PORT failed to load"
  if [ "$APP_PORT" != '80; echo PWNED' ]; then
    fail "phase1: APP_PORT was not stored as data (got $APP_PORT)"
  fi
  ok "phase1: metacharacters in a value stay data"

  printf '%s\n' 'DOMAIN_NAME=example.com' 'REF=${DOMAIN_NAME}' "NL=\"\\n\"" > "$_p1_dir/lit.env"
  load_env_safe "$_p1_dir/lit.env" || fail "phase1: literal-value .env failed to load"
  if [ "$REF" != '${DOMAIN_NAME}' ]; then
    fail "phase1: \${DOMAIN_NAME} was expanded (got $REF)"
  fi
  if [ "$NL" != '\n' ]; then
    fail "phase1: backslash-n was not kept literal (got $NL)"
  fi
  ok "phase1: interpolation and backslash-n stay literal"

  . "$ROOT/scripts/tools/helpers/check-domain-aliases.sh"
  _p1_norm=$(baton_normalize_domain_aliases 'www.a.com, www.b.com') || fail "phase1: safe aliases rejected"
  if [ "$_p1_norm" != 'www.a.com www.b.com' ]; then
    fail "phase1: alias normalization got [$_p1_norm]"
  fi
  _p1_empty=$(baton_normalize_domain_aliases '') || fail "phase1: empty aliases rejected"
  if [ -n "$_p1_empty" ]; then
    fail "phase1: empty aliases produced output"
  fi

  _p1_ifs=$IFS
  IFS=' ;{}#/'
  if baton_normalize_domain_aliases 'www.example.com; } location /x { return 200 x; } #'; then
    IFS=$_p1_ifs
    fail "phase1: poisoned IFS accepted an nginx payload"
  fi
  if [ "$IFS" != ' ;{}#/' ]; then
    _p1_got=$IFS
    IFS=$_p1_ifs
    fail "phase1: alias check did not restore IFS (got $_p1_got)"
  fi
  IFS=$_p1_ifs
  ok "phase1: poisoned IFS still rejects alias payload"

  if ! grep -q 'baton_normalize_domain_aliases' "$ROOT/scripts/tools/projects/render-server-conf.sh"; then
    fail "phase1: renderer does not call baton_normalize_domain_aliases"
  fi
  if grep -q 'echo "${DOMAIN_ALIASES' "$ROOT/scripts/tools/projects/render-server-conf.sh"; then
    fail "phase1: renderer still splits aliases with echo"
  fi
  ok "phase1: renderer uses the fixed alias split"

  rm -rf "$_p1_dir"
  unset APP_PORT DOMAIN_NAME REF NL
}

phase1
