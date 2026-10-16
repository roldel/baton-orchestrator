#!/bin/sh
# Charset checks for values envsubst writes into the shared nginx config.
# Each function returns 0 when the value is safe to substitute.

# APP_PORT: decimal integer 1–65535. No sign, no trailing junk.
baton_check_app_port() {
  _bcap=${1-}
  case $_bcap in
    ''|*[!0-9]*) return 1 ;;
  esac
  _bcap_n=$_bcap
  while :; do
    case $_bcap_n in
      0*) _bcap_n=${_bcap_n#0} ;;
      *) break ;;
    esac
  done
  [ -n "$_bcap_n" ] || return 1
  if [ "${#_bcap_n}" -gt 5 ]; then
    return 1
  fi
  if [ "${#_bcap_n}" -eq 5 ] && [ "$_bcap_n" -gt 65535 ]; then
    return 1
  fi
  return 0
}

# Docker network alias: DNS label, no leading hyphen, 1–63 characters.
baton_check_service_alias() {
  _bcsa=${1-}
  case $_bcsa in
    [A-Za-z0-9]*) ;;
    *) return 1 ;;
  esac
  case $_bcsa in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  if [ "${#_bcsa}" -lt 1 ] || [ "${#_bcsa}" -gt 63 ]; then
    return 1
  fi
  return 0
}

# Empty is allowed. A non-empty value must be a single addr-spec with a
# restricted character set so it cannot become an nginx token.
baton_check_admin_email() {
  _bcae=${1-}
  [ -n "$_bcae" ] || return 0
  case $_bcae in
    *@*) ;;
    *) return 1 ;;
  esac
  _bcae_local=${_bcae%%@*}
  _bcae_domain=${_bcae#*@}
  [ -n "$_bcae_local" ] && [ -n "$_bcae_domain" ] || return 1
  case $_bcae_domain in
    *@*) return 1 ;;
  esac
  case $_bcae_local in
    *[!A-Za-z0-9._%+-]*) return 1 ;;
  esac
  case $_bcae_domain in
    *[!A-Za-z0-9.-]*) return 1 ;;
  esac
  return 0
}

# Same rule as validate-exists.sh: non-empty, not . or .., no slash.
baton_check_project_name() {
  case ${1-} in
    ''|.|..|*/*) return 1 ;;
    *) return 0 ;;
  esac
}
