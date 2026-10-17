#!/bin/sh
# Task-file and path checks for the webhook worker.
# Source this file. Roots default to the host layout and can be overridden
# with BATON_PROJECTS_ROOT, BATON_REPOS_ROOT, BATON_CI_ROOT, BATON_SCRIPTS_ROOT.

# Read a task file. Export only the allowlisted keys. Any other key is an
# error and is not assigned. Values are kept verbatim, including quotes.
baton_load_task_file() {
  _bltf_file=$1
  _bltf_line=0
  while IFS= read -r _bltf_raw || [ -n "$_bltf_raw" ]; do
    _bltf_line=$((_bltf_line + 1))
    case $_bltf_raw in
      ''|'#'*) continue ;;
    esac
    case $_bltf_raw in
      *=*) ;;
      *)
        echo "[load-task] ERROR: $_bltf_file:$_bltf_line: not a KEY=VALUE line" >&2
        return 1
        ;;
    esac
    _bltf_key=${_bltf_raw%%=*}
    _bltf_val=${_bltf_raw#*=}
    case $_bltf_key in
      PROJECT|TARGET_BRANCH|REPO_LOCATION|DOCKER_COMPOSE_RESTART_REQUIRED|CI_PIPELINE_LOCATION|CUSTOM_REDEPLOY_SCRIPT_LOCATION)
        ;;
      *)
        echo "[load-task] ERROR: $_bltf_file:$_bltf_line: key $_bltf_key is not allowed in a task file" >&2
        return 1
        ;;
    esac
    eval "$_bltf_key=\"\$_bltf_val\""
    eval "export $_bltf_key"
  done < "$_bltf_file"
  unset _bltf_file _bltf_line _bltf_raw _bltf_key _bltf_val
}

# Print the physical path of an existing directory.
baton_resolve_dir() {
  _brd=$1
  [ -d "$_brd" ] || return 1
  (CDPATH= cd -- "$_brd" && pwd -P)
}

# Print the allowed physical repo path, or return 1.
# $1 project name, $2 raw REPO_LOCATION.
baton_repo_allowed() {
  _bra_project=$1
  _bra_raw=$2
  _bra_projects=${BATON_PROJECTS_ROOT:-/srv/projects}
  _bra_repos=${BATON_REPOS_ROOT:-/srv/repos}
  _bra_resolved=$(baton_resolve_dir "$_bra_raw") || {
    echo "[repo] ERROR: REPO_LOCATION is not a directory: $_bra_raw" >&2
    return 1
  }
  _bra_projects_phys=$(baton_resolve_dir "$_bra_projects") || {
    echo "[repo] ERROR: projects root is not a directory: $_bra_projects" >&2
    return 1
  }
  if [ "$_bra_resolved" = "$_bra_projects_phys/$_bra_project" ]; then
    printf '%s\n' "$_bra_resolved"
    return 0
  fi
  # A checkout lives at /srv/repos/<this project>, or in a directory under it.
  if [ -d "$_bra_repos" ]; then
    _bra_repos_phys=$(baton_resolve_dir "$_bra_repos") || return 1
    if [ "$_bra_resolved" = "$_bra_repos_phys/$_bra_project" ]; then
      printf '%s\n' "$_bra_resolved"
      return 0
    fi
    case $_bra_resolved in
      "$_bra_repos_phys/$_bra_project"/*)
        printf '%s\n' "$_bra_resolved"
        return 0
        ;;
    esac
  fi
  _bra_repos_phys=${_bra_repos_phys:-$_bra_repos}
  echo "[repo] ERROR: REPO_LOCATION $_bra_resolved must be $_bra_projects_phys/$_bra_project or $_bra_repos_phys/$_bra_project" >&2
  return 1
}

# Resolve a regular file, following symlinks, and print its physical path.
baton_resolve_file() {
  _brf=$1
  _brf_n=0
  while [ -L "$_brf" ]; do
    _brf_n=$((_brf_n + 1))
    [ "$_brf_n" -le 20 ] || return 1
    _brf_target=$(readlink -- "$_brf") || return 1
    case $_brf_target in
      /*) _brf=$_brf_target ;;
      *) _brf=$(dirname -- "$_brf")/$_brf_target ;;
    esac
  done
  [ -f "$_brf" ] || return 1
  [ -d "$_brf" ] && return 1
  _brf_dir=$(dirname -- "$_brf")
  _brf_base=$(basename -- "$_brf")
  _brf_pdir=$(CDPATH= cd -- "$_brf_dir" && pwd -P) || return 1
  printf '%s\n' "$_brf_pdir/$_brf_base"
}

# $1 script path, $2 resolved repo. Print the physical path of an executable
# file that stays inside the repo, the CI root, or the scripts root.
baton_script_allowed() {
  _bsa_script=$1
  _bsa_repo=$2
  _bsa_ci=${BATON_CI_ROOT:-/srv/ci}
  _bsa_scripts=${BATON_SCRIPTS_ROOT:-/srv/scripts}
  _bsa_resolved=$(baton_resolve_file "$_bsa_script") || {
    echo "[script] ERROR: not a regular file: $_bsa_script" >&2
    return 1
  }
  [ -x "$_bsa_resolved" ] || {
    echo "[script] ERROR: not executable: $_bsa_resolved" >&2
    return 1
  }
  _bsa_ok=1
  case $_bsa_resolved in
    "$_bsa_repo"/*) _bsa_ok=0 ;;
  esac
  if [ -d "$_bsa_ci" ]; then
    _bsa_ci_phys=$(baton_resolve_dir "$_bsa_ci") || return 1
    case $_bsa_resolved in
      "$_bsa_ci_phys"/*) _bsa_ok=0 ;;
    esac
  fi
  if [ -d "$_bsa_scripts" ]; then
    _bsa_sc_phys=$(baton_resolve_dir "$_bsa_scripts") || return 1
    case $_bsa_resolved in
      "$_bsa_sc_phys"/*) _bsa_ok=0 ;;
    esac
  fi
  if [ "$_bsa_ok" -ne 0 ]; then
    echo "[script] ERROR: $_bsa_resolved is outside the repo, $_bsa_ci, and $_bsa_scripts" >&2
    return 1
  fi
  printf '%s\n' "$_bsa_resolved"
}

# Print the git config path for a repo, or return 1 when it has no .git.
baton_git_config_file() {
  _bgcf_repo=$1
  if [ -d "$_bgcf_repo/.git" ]; then
    printf '%s\n' "$_bgcf_repo/.git/config"
    return 0
  fi
  if [ ! -f "$_bgcf_repo/.git" ]; then
    return 1
  fi
  _bgcf_gitdir=
  while IFS= read -r _bgcf_line || [ -n "$_bgcf_line" ]; do
    case $_bgcf_line in
      gitdir:*)
        _bgcf_gitdir=${_bgcf_line#gitdir:}
        _bgcf_gitdir=${_bgcf_gitdir# }
        break
        ;;
    esac
  done < "$_bgcf_repo/.git"
  [ -n "$_bgcf_gitdir" ] || return 1
  case $_bgcf_gitdir in
    /*) ;;
    *) _bgcf_gitdir=$_bgcf_repo/$_bgcf_gitdir ;;
  esac
  printf '%s\n' "$_bgcf_gitdir/config"
}

# Remotes and branches stay. Filters, hooks, includes, and other keys do not.
baton_git_key_allowed() {
  case $1 in
    core.repositoryformatversion|core.filemode|core.bare|core.logallrefupdates|core.symlinks|core.ignorecase)
      return 0
      ;;
    remote.*.url|remote.*.fetch|remote.*.mirror|remote.*.tagopt)
      return 0
      ;;
    branch.*.remote|branch.*.merge)
      return 0
      ;;
  esac
  return 1
}

baton_git_config_cmd() {
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git "$@"
}

# Rewrite the repo config so only remotes and branches remain.
baton_sanitize_git_config() {
  _bsg_repo=$1
  _bsg_cfg=$(baton_git_config_file "$_bsg_repo") || return 0
  [ -f "$_bsg_cfg" ] || return 0
  _bsg_list=$(mktemp)
  _bsg_tmp=$(mktemp)
  if ! baton_git_config_cmd config --file "$_bsg_cfg" --list >"$_bsg_list"; then
    rm -f "$_bsg_list" "$_bsg_tmp"
    echo "[git] ERROR: cannot read $_bsg_cfg" >&2
    return 1
  fi
  _bsg_kept=0
  while IFS= read -r _bsg_line || [ -n "$_bsg_line" ]; do
    case $_bsg_line in
      *=*) ;;
      *) continue ;;
    esac
    _bsg_key=${_bsg_line%%=*}
    _bsg_val=${_bsg_line#*=}
    baton_git_key_allowed "$_bsg_key" || continue
    if ! baton_git_config_cmd config --file "$_bsg_tmp" --add "$_bsg_key" "$_bsg_val"; then
      rm -f "$_bsg_list" "$_bsg_tmp"
      echo "[git] ERROR: cannot rewrite $_bsg_cfg" >&2
      return 1
    fi
    _bsg_kept=1
  done < "$_bsg_list"
  if [ "$_bsg_kept" -eq 0 ]; then
    if ! baton_git_config_cmd config --file "$_bsg_tmp" core.repositoryformatversion 0; then
      rm -f "$_bsg_list" "$_bsg_tmp"
      echo "[git] ERROR: cannot rewrite $_bsg_cfg" >&2
      return 1
    fi
  fi
  if ! mv -f "$_bsg_tmp" "$_bsg_cfg"; then
    rm -f "$_bsg_list" "$_bsg_tmp"
    return 1
  fi
  rm -f "$_bsg_list"
  return 0
}

# git with repository code execution turned off. $1 is the resolved repo.
# Remaining args are the git subcommand. A trailing -- belongs with those args:
# this git treats "--" before a revision as a pathspec.
baton_git() {
  _bg_repo=$1
  shift
  if ! baton_sanitize_git_config "$_bg_repo"; then
    echo "[git] ERROR: could not sanitize git config in $_bg_repo" >&2
    return 1
  fi
  env -i \
    PATH="$PATH" \
    HOME="${HOME:-/tmp}" \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    git \
      -c "safe.directory=$_bg_repo" \
      -c core.hooksPath=/dev/null \
      -c core.fsmonitor= \
      -c core.sshCommand=ssh \
      -c protocol.ext.allow=never \
      -c protocol.file.allow=never \
      -c credential.helper= \
      "$@"
}

# uid 65532 / name baton, for setpriv and su. Numeric chgrp does not need it.
baton_ensure_webhook_user() {
  if ! awk -F: '$3 == 65532 { found=1 } END { exit found ? 0 : 1 }' /etc/group; then
    if command -v groupadd >/dev/null 2>&1; then
      groupadd -g 65532 baton || return 1
    elif command -v addgroup >/dev/null 2>&1; then
      addgroup -g 65532 baton || return 1
    else
      echo "[user] ERROR: cannot create gid 65532" >&2
      return 1
    fi
  fi
  if ! awk -F: '$3 == 65532 { found=1 } END { exit found ? 0 : 1 }' /etc/passwd; then
    if command -v useradd >/dev/null 2>&1; then
      useradd -M -u 65532 -g 65532 -s /bin/sh baton || return 1
    elif command -v adduser >/dev/null 2>&1; then
      adduser -D -H -u 65532 -G baton -s /bin/sh baton || return 1
    else
      echo "[user] ERROR: cannot create uid 65532" >&2
      return 1
    fi
  fi
  return 0
}

# Single-quote a string for /bin/sh.
baton_shell_quote() {
  _bsq=$1
  _bsq_out=
  while [ -n "$_bsq" ]; do
    case $_bsq in
      *\'*)
        _bsq_out="${_bsq_out}'${_bsq%%\'*}'\\''"
        _bsq=${_bsq#*\'}
        ;;
      *)
        _bsq_out="${_bsq_out}'${_bsq}'"
        _bsq=
        ;;
    esac
  done
  printf '%s' "$_bsq_out"
}

# Run an executable as uid/gid 65532 with a clean environment.
# Returns 1 when privileges cannot be dropped. Does not fall back to root.
# $1 script, $2 repo directory (group 65532 receives access to this tree).
baton_run_as_webhook_user() {
  _bru_script=$1
  _bru_repo=$2
  if [ "$(id -u)" -eq 65532 ]; then
    env -i PATH="$PATH" HOME="${HOME:-/tmp}" "$_bru_script"
    return $?
  fi
  if [ "$(id -u)" -ne 0 ]; then
    echo "[run] ERROR: cannot run $_bru_script as uid 65532" >&2
    return 1
  fi
  if ! baton_ensure_webhook_user; then
    echo "[run] ERROR: cannot create uid 65532" >&2
    return 1
  fi
  if ! chgrp -R 65532 "$_bru_repo"; then
    echo "[run] ERROR: cannot give group 65532 access to $_bru_repo" >&2
    return 1
  fi
  chmod -R g+rwX "$_bru_repo" || return 1
  chgrp 65532 "$_bru_script" || return 1
  chmod g+rx "$_bru_script" || return 1
  _bru_home="$_bru_repo/.baton-run-home"
  mkdir -p "$_bru_home" || return 1
  chown 65532:65532 "$_bru_home" || return 1
  chmod 0700 "$_bru_home" || return 1
  if command -v setpriv >/dev/null 2>&1; then
    env -i PATH="$PATH" HOME="$_bru_home" \
      setpriv --reuid 65532 --regid 65532 --init-groups --inh-caps=-all \
      -- "$_bru_script"
    return $?
  fi
  if command -v su >/dev/null 2>&1; then
    _bru_q=$(baton_shell_quote "$_bru_script")
    env -i PATH="$PATH" HOME="$_bru_home" \
      su -s /bin/sh baton -c "exec $_bru_q"
    return $?
  fi
  echo "[run] ERROR: neither setpriv nor su is available" >&2
  return 1
}
