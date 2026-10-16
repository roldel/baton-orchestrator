# Phase 4 — shared .env rules, host conflicts, coalesce keeps YES.

phase4() {
  _p4=$(mktemp -d)
  cat > "$_p4/sample.env" << 'EOF'
CMD='$(echo)'
DOMAIN_NAME=example.com
REF=${DOMAIN_NAME}
NL="\n"
NOTE=hello # comment
HASH="keep # hash"
EOF
  printf '%s\n' 'export DOMAIN_NAME=example.com' > "$_p4/export.env"

  (
    . "$ROOT/scripts/tools/helpers/load-env-safe.sh"
    load_env_safe "$_p4/sample.env" || exit 1
    printf '%s\0' "$CMD" "$REF" "$NL" "$NOTE" "$HASH"
  ) > "$_p4/shell.out" || fail "phase4: shell parser rejected the shared fixture"

  if (
    . "$ROOT/scripts/tools/helpers/load-env-safe.sh"
    load_env_safe "$_p4/export.env"
  ); then
    fail "phase4: shell parser accepted an export prefix"
  fi

  ROOT_DIR=$ROOT FIXTURE=$_p4 python3 - << 'PY' || fail "phase4: python parser disagreed"
import os, sys
sys.path.insert(0, os.path.join(os.environ["ROOT_DIR"], "orchestrator", "webhook"))
from envfile import parse_env_file, EnvParseError, find_project_by_host, HostConflict

fix = os.environ["FIXTURE"]
env = parse_env_file(os.path.join(fix, "sample.env"))
shell = open(os.path.join(fix, "shell.out"), "rb").read().split(b"\0")
want = [env["CMD"], env["REF"], env["NL"], env["NOTE"], env["HASH"]]
got = [s.decode("utf-8") for s in shell[:5]]
if want != got:
    sys.stderr.write("python %r\nshell  %r\n" % (want, got))
    sys.exit(1)
if env["REF"] != "${DOMAIN_NAME}" or env["NL"] != "\\n" or env["CMD"] != "$(echo)":
    sys.stderr.write("literals changed: %r\n" % env)
    sys.exit(1)
if env["NOTE"] != "hello" or env["HASH"] != "keep # hash":
    sys.stderr.write("comment handling changed: %r\n" % env)
    sys.exit(1)
try:
    parse_env_file(os.path.join(fix, "export.env"))
except EnvParseError:
    pass
else:
    sys.exit("export was accepted")

root = os.path.join(fix, "projects")
for name in ("a", "b"):
    os.makedirs(os.path.join(root, name))
    with open(os.path.join(root, name, ".env"), "w", encoding="utf-8") as fh:
        fh.write("DOMAIN_NAME=ex.com\n")
locked = os.path.join(root, "000locked")
os.makedirs(locked)
with open(os.path.join(locked, ".env"), "w", encoding="utf-8") as fh:
    fh.write("DOMAIN_NAME=ex.com\n")
os.chmod(locked, 0)
try:
    try:
        find_project_by_host("ex.com", root)
    except HostConflict:
        pass
    else:
        sys.exit("conflict returned a winner")
finally:
    os.chmod(locked, 0o755)
PY
  ok "phase4: parsers agree and overlapping hosts conflict"

  if grep -q 'python-dotenv' "$ROOT/orchestrator/webhook/requirements.txt"; then
    fail "phase4: python-dotenv is still a dependency"
  fi
  if ! grep -q '%Y%m%d-%H%M%S-%f' "$ROOT/orchestrator/webhook/utils.py"; then
    fail "phase4: task names are not microsecond-ordered"
  fi

  . "$ROOT/scripts/tools/webhook/queue-lib.sh"
  log() { :; }
  QUEUE_DIR="$_p4/queue"
  PROCESSED_DIR="$_p4/processed"
  PATTERN='task_*.baton'
  mkdir -p "$QUEUE_DIR" "$PROCESSED_DIR"
  _p4_i=1
  for _p4_flag in NO YES NO; do
    printf '%s\n' "PROJECT=app" "DOCKER_COMPOSE_RESTART_REQUIRED=$_p4_flag" \
      > "$QUEUE_DIR/task_20260101-00000${_p4_i}-00000${_p4_i}_1_x_app.baton"
    _p4_i=$((_p4_i + 1))
  done
  coalesce_queue
  _p4_left=0
  _p4_body=
  for _p4_f in "$QUEUE_DIR"/task_*.baton; do
    [ -f "$_p4_f" ] || continue
    _p4_left=$((_p4_left + 1))
    _p4_body=$(cat "$_p4_f")
  done
  if [ "$_p4_left" -ne 1 ]; then
    fail "phase4: coalesce left $_p4_left task files"
  fi
  case $_p4_body in
    *DOCKER_COMPOSE_RESTART_REQUIRED=YES*) ;;
    *) fail "phase4: survivor lost the YES restart flag" ;;
  esac
  ok "phase4: coalesce keeps YES"

  rm -rf "$_p4"
  unset CMD REF NL NOTE HASH DOMAIN_NAME QUEUE_DIR PROCESSED_DIR PATTERN
}

phase4
