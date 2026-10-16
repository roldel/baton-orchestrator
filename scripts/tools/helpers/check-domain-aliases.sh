#!/bin/sh
# Normalize DOMAIN_ALIASES into a space-separated nginx server_name list.
# Prints the normalized value on stdout. Unsafe tokens go to stderr and the
# function returns 1. Empty input succeeds and prints nothing.
#
# The caller's IFS and noglob are saved and restored. Splitting uses only
# space, tab, newline, and comma, so a poisoned IFS cannot hide a payload
# by turning its punctuation into separators.

baton_normalize_domain_aliases() {
  _bnda_input=${1-}
  _bnda_ifs_set=0
  if [ "${IFS+x}" = x ]; then
    _bnda_ifs_set=1
    _bnda_ifs=$IFS
  fi
  _bnda_opts=$-

  # space, tab, newline — comma is translated to space before the split
  IFS=' 	
'
  set -f

  _bnda_flat=$(printf '%s' "$_bnda_input" | tr ',' ' ' | tr -s ' ' || true)
  _bnda_out=
  _bnda_bad=0

  for _bnda_alias in $_bnda_flat; do
    case "$_bnda_alias" in
      *[!A-Za-z0-9.-]*)
        echo "[check-domain-aliases] ERROR: DOMAIN_ALIASES entry '$_bnda_alias' contains characters unsafe for an nginx server_name (only letters, digits, '.', '-' are allowed)" >&2
        _bnda_bad=1
        break
        ;;
    esac
    if [ -n "$_bnda_out" ]; then
      _bnda_out="$_bnda_out $_bnda_alias"
    else
      _bnda_out=$_bnda_alias
    fi
  done

  if [ "$_bnda_ifs_set" -eq 1 ]; then
    IFS="$_bnda_ifs"
  else
    unset IFS
  fi
  case "$_bnda_opts" in
    *f*) ;;
    *) set +f ;;
  esac

  unset _bnda_input _bnda_ifs_set _bnda_ifs _bnda_opts _bnda_flat _bnda_alias
  if [ "$_bnda_bad" -ne 0 ]; then
    unset _bnda_out _bnda_bad
    return 1
  fi
  printf '%s\n' "$_bnda_out"
  unset _bnda_out _bnda_bad
}
