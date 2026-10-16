#!/bin/sh
# Install or replace one webhook nginx snippet.
# baton_install_webhook_snippet <template> <target> <nginx-test-script> <nginx-reload-script>
# DOMAIN_NAME and WEBHOOK_URL must already be exported. envsubst comes from PATH.
# A matching snippet is a success. A failed test puts the previous file back.

baton_install_webhook_snippet() {
  _bis_template=$1
  _bis_target=$2
  _bis_test=$3
  _bis_reload=$4

  command -v envsubst >/dev/null 2>&1 || {
    echo "[webhook-activate] ERROR: envsubst not found (install gettext)" >&2
    return 1
  }

  _bis_tmp=$(mktemp) || return 1
  if ! envsubst '${DOMAIN_NAME} ${WEBHOOK_URL}' < "$_bis_template" > "$_bis_tmp"; then
    rm -f "$_bis_tmp"
    echo "[webhook-activate] ERROR: envsubst failed" >&2
    return 1
  fi
  if [ ! -s "$_bis_tmp" ]; then
    rm -f "$_bis_tmp"
    echo "[webhook-activate] ERROR: rendered webhook snippet is empty" >&2
    return 1
  fi

  if [ -f "$_bis_target" ] && cmp -s "$_bis_tmp" "$_bis_target"; then
    rm -f "$_bis_tmp"
    return 0
  fi

  _bis_backup=
  if [ -f "$_bis_target" ]; then
    _bis_backup=$(mktemp) || { rm -f "$_bis_tmp"; return 1; }
    if ! cp "$_bis_target" "$_bis_backup"; then
      rm -f "$_bis_tmp" "$_bis_backup"
      return 1
    fi
  fi

  mkdir -p "$(dirname -- "$_bis_target")"
  if ! mv "$_bis_tmp" "$_bis_target"; then
    if [ -n "$_bis_backup" ]; then
      cp "$_bis_backup" "$_bis_target" || {
        rm -f "$_bis_backup"
        return 1
      }
      rm -f "$_bis_backup"
    fi
    return 1
  fi

  if ! sh "$_bis_test"; then
    echo "[webhook-activate] ERROR: nginx test failed" >&2
    if [ -n "$_bis_backup" ]; then
      if ! cp "$_bis_backup" "$_bis_target"; then
        rm -f "$_bis_backup"
        echo "[webhook-activate] ERROR: failed to restore the previous snippet" >&2
        return 1
      fi
      rm -f "$_bis_backup"
    else
      rm -f "$_bis_target"
    fi
    return 1
  fi

  rm -f "$_bis_backup"
  sh "$_bis_reload"
}
