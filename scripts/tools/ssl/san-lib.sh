#!/bin/sh
# Compare an openssl subjectAltName block to an expected name list.
# baton_san_set_matches <san-text> <name> [name...]
# Names are a set: order does not matter, comparison is case-insensitive.
# Returns 0 only when the DNS names are exactly the given names.

baton_dns_names() {
  printf '%s\n' "$1" | tr ',' '\n' | while IFS= read -r _bdn_part || [ -n "$_bdn_part" ]; do
    case $_bdn_part in
      *DNS:*)
        _bdn_name=${_bdn_part#*DNS:}
        _bdn_name=$(printf '%s' "$_bdn_name" | tr -d ' \t\r')
        [ -n "$_bdn_name" ] || continue
        printf '%s\n' "$_bdn_name" | tr '[:upper:]' '[:lower:]'
        ;;
    esac
  done | sed '/^$/d' | sort -u
}

baton_san_set_matches() {
  _bss_text=$1
  shift
  _bss_got=$(baton_dns_names "$_bss_text")
  _bss_want=
  for _bss_name in "$@"; do
    [ -n "$_bss_name" ] || continue
    _bss_want="${_bss_want}$(printf '%s' "$_bss_name" | tr '[:upper:]' '[:lower:]')
"
  done
  _bss_want=$(printf '%s\n' "$_bss_want" | sed '/^$/d' | sort -u)
  [ "$_bss_got" = "$_bss_want" ]
}
