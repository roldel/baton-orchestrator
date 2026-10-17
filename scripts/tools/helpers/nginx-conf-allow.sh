#!/bin/sh
# Line scan of one rendered nginx server file before it is installed.
# This is not an nginx parser. A directive split across lines is rejected
# when this scan cannot see the whole directive on one line.

baton_nca_trim() {
  _bnt=$1
  while :; do
    case $_bnt in
      ' '*) _bnt=${_bnt# } ;;
      *) break ;;
    esac
  done
  while :; do
    case $_bnt in
      *' ') _bnt=${_bnt% } ;;
      *) break ;;
    esac
  done
  case $_bnt in
    *';') _bnt=${_bnt%;} ;;
  esac
  while :; do
    case $_bnt in
      *' ') _bnt=${_bnt% } ;;
      *) break ;;
    esac
  done
  printf '%s' "$_bnt"
}

baton_nca_unquote() {
  _nuq=$1
  case $_nuq in
    \"*\")
      _nuq=${_nuq#\"}
      _nuq=${_nuq%\"}
      ;;
    \'*\')
      _nuq=${_nuq#\'}
      _nuq=${_nuq%\'}
      ;;
  esac
  printf '%s' "$_nuq"
}

baton_nca_save_split() {
  _nca_ifs_set=0
  if [ "${IFS+x}" = x ]; then
    _nca_ifs_set=1
    _nca_ifs=$IFS
  fi
  _nca_opts=$-
  IFS=' 	
'
  set -f
}

baton_nca_restore_split() {
  if [ "${_nca_ifs_set:-0}" -eq 1 ]; then
    IFS="$_nca_ifs"
  else
    unset IFS
  fi
  case ${_nca_opts:-} in
    *f*) ;;
    *) set +f ;;
  esac
}

# $1 token. Domain and aliases are the only server_name values.
baton_nca_name_ok() {
  _nca_name=$1
  case $_nca_name in
    *'*'*|*'?'*|*'['*|*' '*|*'	'*|*'{'*|*'\'*|*'/'*|*'#'*|'$'*)
      return 1
      ;;
  esac
  [ "$_nca_name" = "$_nca_domain" ] && return 0
  case " ${_nca_aliases} " in
    *" $_nca_name "*) return 0 ;;
  esac
  return 1
}

# $1 path. ACME webroot, or /srv/shared-files/<site> and its children.
baton_nca_path_ok() {
  _nca_path=$1
  case $_nca_path in
    *'$'*|*'..'*|*' '*|*'	'*|*'#'*) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  while :; do
    case $_nca_path in
      */)
        [ "$_nca_path" = / ] && break
        _nca_path=${_nca_path%/}
        ;;
      *) break ;;
    esac
  done
  _nca_acme=/var/www/acme-challenge
  [ "$_nca_path" = "$_nca_acme" ] && return 0
  case $_nca_path in
    "$_nca_acme"/*) return 0 ;;
  esac
  if [ -n "${_nca_site:-}" ]; then
    _nca_site_root=/srv/shared-files/$_nca_site
    [ "$_nca_path" = "$_nca_site_root" ] && return 0
    case $_nca_path in
      "$_nca_site_root"/*) return 0 ;;
    esac
  fi
  return 1
}

baton_nca_forbidden() {
  _bnf=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case $_bnf in
    *default_server*) return 0 ;;
    load_module|load_module\ *|load_module\;*) return 0 ;;
    perl|perl\ *|perl\;*) return 0 ;;
    perl_set*|perl_modules*|lua_*|js_*) return 0 ;;
    fastcgi_pass*|uwsgi_pass*|scgi_pass*|grpc_pass*|memcached_pass*) return 0 ;;
    *' load_module '*|*' load_module;'*) return 0 ;;
    *' perl_set'*|*' perl_modules'*|*' lua_'*|*' js_'*) return 0 ;;
    *' fastcgi_pass'*|*' uwsgi_pass'*|*' scgi_pass'*|*' grpc_pass'*|*' memcached_pass'*) return 0 ;;
  esac
  return 1
}

# $1 directive word, $2 trimmed line.
baton_nca_check_directive() {
  _nca_dir=$1
  _nca_full=$2
  _nca_rest=$(baton_nca_trim "${_nca_full#"$_nca_dir"}")
  _nca_rest=$(baton_nca_unquote "$_nca_rest")
  case $_nca_dir in
    server_name)
      baton_nca_save_split
      _nca_names_bad=0
      for _nca_tok in $_nca_rest; do
        [ -n "$_nca_tok" ] || continue
        if ! baton_nca_name_ok "$_nca_tok"; then
          echo "[nginx-conf] ERROR: server_name '$_nca_tok' is not $_nca_domain or one of its aliases" >&2
          _nca_names_bad=1
          break
        fi
      done
      baton_nca_restore_split
      [ "$_nca_names_bad" -eq 0 ] || return 1
      ;;
    listen)
      baton_nca_save_split
      _nca_addr=
      _nca_listen_bad=0
      for _nca_tok in $_nca_rest; do
        [ -n "$_nca_tok" ] || continue
        if [ -z "$_nca_addr" ]; then
          _nca_addr=$_nca_tok
          if [ "$_nca_addr" != 80 ] && [ "$_nca_addr" != '[::]:80' ] \
              && [ "$_nca_addr" != 443 ] && [ "$_nca_addr" != '[::]:443' ]; then
            echo "[nginx-conf] ERROR: listen address is not allowed: $_nca_addr" >&2
            _nca_listen_bad=1
            break
          fi
          continue
        fi
        case $_nca_tok in
          ssl|http2|reuseport|so_keepalive=on) ;;
          *)
            echo "[nginx-conf] ERROR: listen flag is not allowed: $_nca_tok" >&2
            _nca_listen_bad=1
            break
            ;;
        esac
      done
      baton_nca_restore_split
      [ -n "$_nca_addr" ] || {
        echo "[nginx-conf] ERROR: listen has no address" >&2
        return 1
      }
      [ "$_nca_listen_bad" -eq 0 ] || return 1
      ;;
    ssl_certificate|ssl_certificate_key)
      if [ "$_nca_dir" = ssl_certificate ]; then
        _nca_want="/etc/letsencrypt/live/${_nca_domain}/fullchain.pem"
      else
        _nca_want="/etc/letsencrypt/live/${_nca_domain}/privkey.pem"
      fi
      if [ "$_nca_rest" != "$_nca_want" ]; then
        echo "[nginx-conf] ERROR: $_nca_dir must be $_nca_want" >&2
        return 1
      fi
      ;;
    include)
      _nca_want="/etc/nginx/webhooks.d/${_nca_domain}-*.conf"
      if [ "$_nca_rest" != "$_nca_want" ]; then
        echo "[nginx-conf] ERROR: include is not allowed: $_nca_rest" >&2
        return 1
      fi
      ;;
    root|alias)
      if ! baton_nca_path_ok "$_nca_rest"; then
        echo "[nginx-conf] ERROR: $_nca_dir path is outside the allowed roots: $_nca_rest" >&2
        return 1
      fi
      ;;
    proxy_pass)
      if [ -z "${_nca_upstream:-}" ] || [ -z "${_nca_port:-}" ]; then
        echo "[nginx-conf] ERROR: proxy_pass is not allowed for this site" >&2
        return 1
      fi
      case $_nca_rest in
        *'$'*)
          echo "[nginx-conf] ERROR: proxy_pass contains a variable: $_nca_rest" >&2
          return 1
          ;;
      esac
      _nca_http="http://${_nca_upstream}:${_nca_port}"
      _nca_https="https://${_nca_upstream}:${_nca_port}"
      if [ "$_nca_rest" = "$_nca_http" ] || [ "$_nca_rest" = "$_nca_https" ]; then
        return 0
      fi
      case $_nca_rest in
        "$_nca_http"/*|"$_nca_https"/*) return 0 ;;
      esac
      echo "[nginx-conf] ERROR: proxy_pass is not $_nca_http: $_nca_rest" >&2
      return 1
      ;;
  esac
  return 0
}

# baton_check_rendered_conf FILE DOMAIN ALIASES SITE_KEY UPSTREAM PORT
# Aliases are space-separated. Empty upstream or port rejects every proxy_pass.
baton_check_rendered_conf() {
  _nca_file=$1
  _nca_domain=$2
  _nca_aliases=$3
  _nca_site=$4
  _nca_upstream=$5
  _nca_port=$6

  if [ ! -f "$_nca_file" ]; then
    echo "[nginx-conf] ERROR: not a file: $_nca_file" >&2
    return 1
  fi
  if [ -z "$_nca_domain" ]; then
    echo "[nginx-conf] ERROR: domain is empty" >&2
    return 1
  fi

  while IFS= read -r _nca_raw || [ -n "$_nca_raw" ]; do
    _nca_line=${_nca_raw%%#*}
    _nca_line=$(printf '%s' "$_nca_line" | tr '\t' ' ')
    _nca_line=$(baton_nca_trim "$_nca_line")
    [ -n "$_nca_line" ] || continue
    if baton_nca_forbidden "$_nca_line"; then
      echo "[nginx-conf] ERROR: forbidden directive: $_nca_line" >&2
      return 1
    fi
    _nca_word=${_nca_line%% *}
    case $_nca_word in
      server_name|listen|ssl_certificate|ssl_certificate_key|include|root|alias|proxy_pass)
        baton_nca_check_directive "$_nca_word" "$_nca_line" || return 1
        ;;
      ssl_*)
        case $_nca_word in
          *certificate*)
            echo "[nginx-conf] ERROR: certificate directive is not allowed: $_nca_line" >&2
            return 1
            ;;
        esac
        ;;
    esac
  done < "$_nca_file"
  return 0
}
