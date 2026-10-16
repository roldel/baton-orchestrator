#!/bin/sh
# Static publish helpers: reject symlinks that leave the tree, swap the
# live symlink in one rename, and sweep abandoned staging directories.

# Collapse "." and ".." without looking at the filesystem.
baton_collapse_path() {
  _bcp=$1
  _bcp_abs=0
  case $_bcp in
    /*) _bcp_abs=1 ;;
  esac
  _bcp_ifs_set=0
  if [ "${IFS+x}" = x ]; then
    _bcp_ifs_set=1
    _bcp_ifs=$IFS
  fi
  _bcp_opts=$-
  IFS=/
  set -f
  _bcp_out=
  for _bcp_seg in $_bcp; do
    case $_bcp_seg in
      ''|.) continue ;;
      ..)
        case $_bcp_out in
          '')
            if [ "$_bcp_abs" -eq 0 ]; then
              _bcp_out=..
            fi
            ;;
          ..|../*)
            _bcp_out=$_bcp_out/..
            ;;
          */*)
            _bcp_out=${_bcp_out%/*}
            ;;
          *)
            _bcp_out=
            ;;
        esac
        ;;
      *)
        if [ -n "$_bcp_out" ]; then
          _bcp_out=$_bcp_out/$_bcp_seg
        else
          _bcp_out=$_bcp_seg
        fi
        ;;
    esac
  done
  if [ "$_bcp_ifs_set" -eq 1 ]; then
    IFS="$_bcp_ifs"
  else
    unset IFS
  fi
  case $_bcp_opts in
    *f*) ;;
    *) set +f ;;
  esac
  if [ "$_bcp_abs" -eq 1 ]; then
    if [ -n "$_bcp_out" ]; then
      printf '/%s\n' "$_bcp_out"
    else
      printf '/\n'
    fi
  else
    printf '%s\n' "$_bcp_out"
  fi
}

# Return 1 if any symlink resolves outside $1. The target does not need to exist.
baton_reject_escaping_symlinks() {
  _bre_root=$1
  while IFS= read -r _bre_link || [ -n "$_bre_link" ]; do
    [ -n "$_bre_link" ] || continue
    [ -L "$_bre_link" ] || continue
    _bre_target=$(readlink -- "$_bre_link") || return 1
    _bre_parent=$(dirname -- "$_bre_link")
    case $_bre_target in
      /*) _bre_joined=$_bre_target ;;
      *) _bre_joined=$_bre_parent/$_bre_target ;;
    esac
    _bre_norm=$(baton_collapse_path "$_bre_joined")
    case $_bre_norm in
      "$_bre_root"|"$_bre_root"/*) ;;
      *)
        echo "[sync-static-site] ERROR: symlink $_bre_link points outside the release tree ($_bre_norm)" >&2
        return 1
        ;;
    esac
  done <<EOF
$(find "$_bre_root" -type l 2>/dev/null || true)
EOF
}

# Point $2 at $1 by renaming a new symlink onto $2.
baton_atomic_symlink() {
  _bas_target=$1
  _bas_dest=$2
  _bas_tmp=${_bas_dest}.tmp.$$
  ln -s "$_bas_target" "$_bas_tmp"
  mv -f "$_bas_tmp" "$_bas_dest"
}

# Delete .staging-<timestamp>-* directories older than one day.
# $1 releases dir, $2 path that must not be deleted (the live target).
baton_sweep_staging() {
  _sw_dir=$1
  _sw_live=${2-}
  _sw_cut=$(date -d "@$(($(date +%s) - 86400))" '+%Y%m%d-%H%M%S')
  for _sw_path in "$_sw_dir"/.staging-*; do
    [ -e "$_sw_path" ] || continue
    if [ -n "$_sw_live" ] && [ "$_sw_path" = "$_sw_live" ]; then
      continue
    fi
    _sw_base=$(basename -- "$_sw_path")
    _sw_rest=${_sw_base#.staging-}
    _sw_pid=${_sw_rest##*-}
    _sw_ts=${_sw_rest%-"$_sw_pid"}
    _sw_first=$(printf '%s\n%s\n' "$_sw_ts" "$_sw_cut" | sort | head -n 1)
    if [ "$_sw_first" = "$_sw_ts" ] && [ "$_sw_ts" != "$_sw_cut" ]; then
      rm -rf "$_sw_path"
    fi
  done
}
