# Phase 3 — webhook worker confinement.

phase3() {
  . "$ROOT/scripts/tools/webhook/task-lib.sh"
  _p3=$(mktemp -d)

  printf '%s\n' 'PATH=/tmp/evil' > "$_p3/task"
  _p3_path=$PATH
  if baton_load_task_file "$_p3/task"; then
    fail "phase3: PATH key in a task file was accepted"
  fi
  if [ "$PATH" != "$_p3_path" ]; then
    fail "phase3: task loader changed PATH"
  fi
  ok "phase3: task loader rejects PATH"

  printf '%s\n' 'PROJECT=my"proj' > "$_p3/quote"
  baton_load_task_file "$_p3/quote" || fail "phase3: quoted-character project failed to load"
  if [ "$PROJECT" != 'my"proj' ]; then
    fail "phase3: task value lost a quote (got $PROJECT)"
  fi
  unset PROJECT

  _p3_projects="$_p3/projects"
  _p3_repos="$_p3/repos"
  mkdir -p "$_p3_projects/mine" "$_p3_projects/other" "$_p3_projects/mine-evil" "$_p3_repos/mine"
  BATON_PROJECTS_ROOT=$_p3_projects
  BATON_REPOS_ROOT=$_p3_repos
  export BATON_PROJECTS_ROOT BATON_REPOS_ROOT

  if baton_repo_allowed mine / >/dev/null; then
    fail "phase3: REPO_LOCATION=/ was accepted"
  fi
  if baton_repo_allowed mine "$_p3_projects/other" >/dev/null; then
    fail "phase3: another project's directory was accepted"
  fi
  if baton_repo_allowed mine "$_p3_projects/mine-evil" >/dev/null; then
    fail "phase3: slash-boundary bypass was accepted"
  fi
  _p3_got=$(baton_repo_allowed mine "$_p3_projects/mine") || fail "phase3: project repo rejected"
  [ -n "$_p3_got" ] || fail "phase3: project repo printed nothing"
  baton_repo_allowed mine "$_p3_repos/mine" >/dev/null || fail "phase3: /repos path rejected"
  ok "phase3: repo roots"

  _p3_repo=$(baton_repo_allowed mine "$_p3_projects/mine")
  mkdir -p "$_p3/ci" "$_p3/scripts"
  BATON_CI_ROOT=$_p3/ci
  BATON_SCRIPTS_ROOT=$_p3/scripts
  export BATON_CI_ROOT BATON_SCRIPTS_ROOT
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$_p3/ci/build.sh"
  chmod 755 "$_p3/ci/build.sh"
  baton_script_allowed "$_p3/ci/build.sh" "$_p3_repo" >/dev/null || fail "phase3: CI script under /srv/ci rejected"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$_p3/outside.sh"
  chmod 755 "$_p3/outside.sh"
  if baton_script_allowed "$_p3/outside.sh" "$_p3_repo" >/dev/null; then
    fail "phase3: script outside the roots was accepted"
  fi
  ok "phase3: script roots"

  if ! grep -q 'core.hooksPath=/dev/null' "$ROOT/scripts/tools/webhook/task-lib.sh"; then
    fail "phase3: git command missing hooksPath"
  fi
  if ! grep -q 'baton_git' "$ROOT/scripts/tools/webhook/handle-webhook.sh"; then
    fail "phase3: handler does not call baton_git"
  fi
  if grep -q 'baton-handle.lock' "$ROOT/scripts/tools/webhook/handle-webhook.sh"; then
    fail "phase3: directory lock is still present"
  fi
  if ! grep -q 'exec flock -o -w 60' "$ROOT/scripts/tools/webhook/handle-webhook.sh"; then
    fail "phase3: handler does not flock"
  fi

  _p3_git=$(mktemp -d)
  git -C "$_p3_git" init -q -b main
  git -C "$_p3_git" config user.email t@example.com
  git -C "$_p3_git" config user.name t
  echo a > "$_p3_git/f"
  git -C "$_p3_git" add f
  git -C "$_p3_git" commit -q -m init
  mkdir -p "$_p3_git/.git/hooks"
  printf '%s\n' '#!/bin/sh' "echo hooked > '$_p3_git/hook-ran'" > "$_p3_git/.git/hooks/post-checkout"
  chmod 755 "$_p3_git/.git/hooks/post-checkout"
  baton_git "$_p3_git" -C "$_p3_git" checkout -B other HEAD -- || fail "phase3: guarded checkout failed"
  if [ -f "$_p3_git/hook-ran" ]; then
    fail "phase3: post-checkout hook ran"
  fi
  ok "phase3: git hooks disabled"

  _p3_lock="$_p3/lock"
  # -o: only the flock parent holds the fd. Killing that parent releases
  # the lock even though the child is still alive.
  flock -o "$_p3_lock" sh -c 'echo held; exec sleep 30' > "$_p3/held" &
  _p3_pid=$!
  _p3_i=0
  while [ ! -s "$_p3/held" ] && [ "$_p3_i" -lt 50 ]; do
    sleep 0.1
    _p3_i=$((_p3_i + 1))
  done
  if flock -n "$_p3_lock" true; then
    kill -9 "$_p3_pid" 2>/dev/null || true
    fail "phase3: lock was not held"
  fi
  kill -9 "$_p3_pid" 2>/dev/null || true
  wait "$_p3_pid" 2>/dev/null || true
  if ! flock -w 2 "$_p3_lock" true; then
    fail "phase3: lock was not released after SIGKILL"
  fi
  for _p3_proc in /proc/[0-9]*; do
    _p3_cmd=$(tr '\0' ' ' < "$_p3_proc/cmdline" 2>/dev/null || true)
    if [ "$_p3_cmd" = "sleep 30 " ] || [ "$_p3_cmd" = "sleep 30" ]; then
      kill -9 "${_p3_proc#/proc/}" 2>/dev/null || true
    fi
  done
  ok "phase3: flock releases on SIGKILL"

  if ! grep -q '65532' "$ROOT/orchestrator/webhook/Dockerfile"; then
    fail "phase3: image is not uid 65532"
  fi
  if ! grep -q 'chown 65532:65532' "$ROOT/scripts/setup.sh"; then
    fail "phase3: setup.sh does not chown the queue to 65532"
  fi
  if ! grep -q 'chmod 0700' "$ROOT/scripts/setup.sh"; then
    fail "phase3: setup.sh does not set queue mode 0700"
  fi
  if ! grep -q 'chown 65532:65532' "$ROOT/scripts/tools/webhook/service-file.sh"; then
    fail "phase3: service start_pre does not chown the queue"
  fi
  ok "phase3: queue uid and mode"

  rm -rf "$_p3" "$_p3_git"
  unset BATON_PROJECTS_ROOT BATON_REPOS_ROOT BATON_CI_ROOT BATON_SCRIPTS_ROOT PROJECT
}

phase3
