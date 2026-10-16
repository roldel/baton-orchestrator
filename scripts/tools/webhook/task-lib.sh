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
  if [ -d "$_bra_repos" ]; then
    _bra_repos_phys=$(baton_resolve_dir "$_bra_repos") || return 1
    case $_bra_resolved in
      "$_bra_repos_phys"|"$_bra_repos_phys"/*)
        printf '%s\n' "$_bra_resolved"
        return 0
        ;;
    esac
  fi
  echo "[repo] ERROR: REPO_LOCATION $_bra_resolved is outside $_bra_projects_phys/$_bra_project and $_bra_repos" >&2
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

# git with repository code execution turned off. $1 is the resolved repo.
# Remaining args are the git subcommand. A trailing -- belongs with those args:
# this git treats "--" before a revision as a pathspec.
baton_git() {
  _bg_repo=$1
  shift
  command git \
    -c "safe.directory=$_bg_repo" \
    -c core.hooksPath=/dev/null \
    -c core.fsmonitor= \
    -c core.sshCommand=ssh \
    -c protocol.ext.allow=never \
    "$@"
}
