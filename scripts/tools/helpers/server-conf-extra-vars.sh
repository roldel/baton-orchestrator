#!/bin/sh
# Project-declared extra variables for server.conf.
#
# A project .env may list extra names for render-server-conf.sh to substitute:
#
#   SERVER_CONF_EXTRA_VARS=PROXY_AUTH_SECRET
#   SERVER_CONF_EXTRA_VARS="PROXY_AUTH_SECRET UPSTREAM_TOKEN"   # or A,B
#
# baton_server_conf_extra_vars ENV_FILE
#   Prints the declared names, space-separated, on stdout (nothing when the
#   key is absent or empty). Returns 1 after reporting every problem on stderr.
#   The caller must already have sourced load-env-safe.sh. The file is loaded
#   in a subshell, so the caller's variables are never touched.
#
# Every name must match [A-Z_][A-Z0-9_]*, must not be a name baton itself
# substitutes or uses in the renderer, and must be set to a non-empty value
# in ENV_FILE itself (not inherited from the process environment).
#
# Values are treated as secrets: no message here ever prints one. A value is
# written unescaped into the shared nginx config, and the rendered-config scan
# only looks at the first directive on each line, so a value may not contain
# whitespace, quotes, ';', '{', '}', '\', '$' or '#'. Those would let it end
# the directive or the quoted string it sits in and start a new one.

baton_server_conf_extra_vars() {
  (
    set +eu
    _bsce_file=$1
    # Built-in substitution names, plus every upper-case variable the renderer
    # keeps in its own shell. A .env value for one of these would be
    # overwritten or would change the renderer, so it cannot be an extra.
    # Lower-case and set before the load so the .env cannot change the list.
    _bsce_reserved="PROJECT SITE_KEY DOMAIN_NAME DOMAIN_ALIASES DOMAIN_ADMIN_EMAIL WEBHOOK_URL DOCKER_NETWORK_SERVICE_ALIAS APP_PORT STATIC_SITE SERVER_CONF_EXTRA_VARS BASE_DIR PROJECT_DIR ENV_FILE TEMPLATE TMP_DIR MANDATORY_VARS VARS_TO_SUBSTITUTE EXTRA_VARS TEMP_RENDER LEFTOVER"
    load_env_safe "$_bsce_file" || exit 1

    # space, tab, newline — comma is translated to space before the split
    IFS=' 	
'
    set -f

    _bsce_flat=$(printf '%s' "${SERVER_CONF_EXTRA_VARS:-}" | tr ',' ' ')
    _bsce_out=
    _bsce_bad=0

    for _bsce_name in $_bsce_flat; do
      case $_bsce_name in
        [A-Z_]*) ;;
        *)
          echo "[server-conf-extra-vars] ERROR: SERVER_CONF_EXTRA_VARS entry '$_bsce_name' is not a valid name (must match [A-Z_][A-Z0-9_]*)" >&2
          _bsce_bad=1
          continue
          ;;
      esac
      case $_bsce_name in
        *[!A-Z0-9_]*)
          echo "[server-conf-extra-vars] ERROR: SERVER_CONF_EXTRA_VARS entry '$_bsce_name' is not a valid name (must match [A-Z_][A-Z0-9_]*)" >&2
          _bsce_bad=1
          continue
          ;;
      esac
      case " $_bsce_reserved " in
        *" $_bsce_name "*)
          echo "[server-conf-extra-vars] ERROR: SERVER_CONF_EXTRA_VARS entry $_bsce_name is reserved by baton and cannot be declared as an extra variable" >&2
          _bsce_bad=1
          continue
          ;;
      esac
      case " $_bsce_out " in
        *" $_bsce_name "*) continue ;;
      esac

      # The name is now [A-Z_][A-Z0-9_]*, so it is safe in a regex and in eval.
      if ! grep -q "^$_bsce_name=" "$_bsce_file"; then
        echo "[server-conf-extra-vars] ERROR: $_bsce_name is listed in SERVER_CONF_EXTRA_VARS but not set in $_bsce_file" >&2
        _bsce_bad=1
        continue
      fi
      eval "_bsce_val=\${$_bsce_name:-}"
      if [ -z "$_bsce_val" ]; then
        echo "[server-conf-extra-vars] ERROR: $_bsce_name is listed in SERVER_CONF_EXTRA_VARS but empty in $_bsce_file" >&2
        _bsce_bad=1
        continue
      fi
      case $_bsce_val in
        *[\ \	\"\'\;{}\\\$#]*)
          echo "[server-conf-extra-vars] ERROR: $_bsce_name contains characters not allowed in server.conf (whitespace, quotes, ';', '{', '}', '\\', '\$', '#')" >&2
          _bsce_bad=1
          continue
          ;;
      esac

      if [ -n "$_bsce_out" ]; then
        _bsce_out="$_bsce_out $_bsce_name"
      else
        _bsce_out=$_bsce_name
      fi
    done

    [ "$_bsce_bad" -eq 0 ] || exit 1
    [ -z "$_bsce_out" ] || printf '%s\n' "$_bsce_out"
  )
}
