#!/bin/sh
# Scan of `docker compose config` text before compose runs.
# This is not a sandbox. A compose file can still harm the host in ways a
# text scan does not see. The scan rejects the obvious host escapes.

baton_cg_trim() {
  _cgt=$1
  while :; do
    case $_cgt in
      ' '*) _cgt=${_cgt# } ;;
      *) break ;;
    esac
  done
  while :; do
    case $_cgt in
      *' ') _cgt=${_cgt% } ;;
      *) break ;;
    esac
  done
  printf '%s' "$_cgt"
}

baton_cg_unquote() {
  _cgu=$1
  case $_cgu in
    \"*\")
      _cgu=${_cgu#\"}
      _cgu=${_cgu%\"}
      ;;
    \'*\')
      _cgu=${_cgu#\'}
      _cgu=${_cgu%\'}
      ;;
  esac
  printf '%s' "$_cgu"
}

baton_cg_scalar() {
  baton_cg_unquote "$(baton_cg_trim "$1")"
}

# $1 path, $2 root. True when path is the root or a child of it.
baton_cg_under() {
  _cgu_path=$1
  _cgu_root=$2
  while :; do
    case $_cgu_path in
      */)
        [ "$_cgu_path" = / ] && break
        _cgu_path=${_cgu_path%/}
        ;;
      *) break ;;
    esac
  done
  while :; do
    case $_cgu_root in
      */)
        [ "$_cgu_root" = / ] && break
        _cgu_root=${_cgu_root%/}
        ;;
      *) break ;;
    esac
  done
  [ "$_cgu_path" = "$_cgu_root" ] && return 0
  case $_cgu_path in
    "$_cgu_root"/*) return 0 ;;
  esac
  return 1
}

# Absolute binds must stay inside the project directory, or inside the
# project's shared-files directory when one was passed. Relative paths and
# named volumes are left alone. Any ".." segment is rejected.
baton_cg_bind_ok() {
  _cgb=$1
  case $_cgb in
    *..*)
      echo "[compose-guard] ERROR: bind source contains ..: $_cgb" >&2
      return 1
      ;;
    /*)
      if baton_cg_under "$_cgb" "$_cca_log" || baton_cg_under "$_cgb" "$_cca_phys"; then
        return 0
      fi
      if [ -n "${_cca_shared:-}" ] && baton_cg_under "$_cgb" "$_cca_shared"; then
        return 0
      fi
      echo "[compose-guard] ERROR: bind source is outside the project directory: $_cgb" >&2
      return 1
      ;;
  esac
  return 0
}

# Print <shared-files>/<DOMAIN_NAME>, or nothing when DOMAIN_NAME is missing
# or is not one path segment. $1 is the project directory. $2 is the helpers
# directory that contains load-env-safe.sh.
baton_compose_shared_dir() {
  _csd_dir=$1
  _csd_helpers=$2
  [ -f "$_csd_dir/.env" ] || return 0
  [ -f "$_csd_helpers/load-env-safe.sh" ] || return 0
  _csd_domain=$(
    set +e
    . "$_csd_helpers/load-env-safe.sh"
    if load_env_safe "$_csd_dir/.env"; then
      printf '%s' "${DOMAIN_NAME:-}"
    fi
  ) || _csd_domain=""
  case $_csd_domain in
    ''|'.'|'..') return 0 ;;
    *[!A-Za-z0-9.-]*) return 0 ;;
  esac
  _csd_root=${BATON_SHARED_FILES_ROOT:-/srv/shared-files}
  while :; do
    case $_csd_root in
      */)
        [ "$_csd_root" = / ] && break
        _csd_root=${_csd_root%/}
        ;;
      *) break ;;
    esac
  done
  printf '%s' "$_csd_root/$_csd_domain"
}

# baton_compose_config_allowed FILE PROJECT_DIR [SHARED_DIR]
# SHARED_DIR is this project's /srv/shared-files/<DOMAIN_NAME>.
baton_compose_config_allowed() {
  _cca_file=$1
  _cca_dir=$2
  _cca_shared=${3:-}
  if [ ! -f "$_cca_file" ]; then
    echo "[compose-guard] ERROR: not a file: $_cca_file" >&2
    return 1
  fi
  if [ ! -d "$_cca_dir" ]; then
    echo "[compose-guard] ERROR: project directory not found: $_cca_dir" >&2
    return 1
  fi
  _cca_log=$(CDPATH= cd -- "$_cca_dir" && pwd) || return 1
  _cca_phys=$(CDPATH= cd -- "$_cca_dir" && pwd -P) || return 1

  while IFS= read -r _cca_raw || [ -n "$_cca_raw" ]; do
    _cca_line=${_cca_raw%%#*}
    _cca_line=$(printf '%s' "$_cca_line" | tr '\t' ' ')
    _cca_line=$(baton_cg_trim "$_cca_line")
    [ -n "$_cca_line" ] || continue
    _cca_low=$(printf '%s' "$_cca_line" | tr '[:upper:]' '[:lower:]')
    case $_cca_low in
      *docker.sock*)
        echo "[compose-guard] ERROR: docker.sock is not allowed" >&2
        return 1
        ;;
      *sys_admin*)
        echo "[compose-guard] ERROR: SYS_ADMIN is not allowed" >&2
        return 1
        ;;
    esac
    case $_cca_line in
      privileged:*)
        _cca_val=$(baton_cg_scalar "${_cca_line#*:}")
        _cca_val=$(printf '%s' "$_cca_val" | tr '[:upper:]' '[:lower:]')
        case $_cca_val in
          true|yes)
            echo "[compose-guard] ERROR: privileged is not allowed" >&2
            return 1
            ;;
        esac
        ;;
      network_mode:*|pid:*|ipc:*)
        _cca_key=${_cca_line%%:*}
        _cca_val=$(baton_cg_scalar "${_cca_line#*:}")
        _cca_val=$(printf '%s' "$_cca_val" | tr '[:upper:]' '[:lower:]')
        if [ "$_cca_val" = host ]; then
          echo "[compose-guard] ERROR: $_cca_key host is not allowed" >&2
          return 1
        fi
        ;;
      source:*)
        _cca_val=$(baton_cg_scalar "${_cca_line#source:}")
        baton_cg_bind_ok "$_cca_val" || return 1
        ;;
      -*)
        _cca_val=$(baton_cg_scalar "${_cca_line#-}")
        case $_cca_val in
          /*:*)
            baton_cg_bind_ok "${_cca_val%%:*}" || return 1
            ;;
        esac
        ;;
    esac
  done < "$_cca_file"
  return 0
}
