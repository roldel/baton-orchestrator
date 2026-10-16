# Phase 6 — a certificate must name every host nginx will serve.
# A failed certbot delete must not be reported as a reissue.

phase6() {
  _p6=$(mktemp -d)

  . "$ROOT/scripts/tools/ssl/san-lib.sh"
  _p6_san='X509v3 Subject Alternative Name:
    DNS:Example.com, DNS:www.example.com'
  if ! baton_san_set_matches "$_p6_san" WWW.example.com example.com; then
    fail "phase6: exact SAN set was rejected"
  fi
  if baton_san_set_matches "$_p6_san" example.com; then
    fail "phase6: a cert with an extra name matched a shorter list"
  fi
  if baton_san_set_matches "$_p6_san" example.com www.example.com api.example.com; then
    fail "phase6: a missing alias was accepted"
  fi
  ok "phase6: SAN set equality"

  # delete fails and the pems stay. ensure-certs must not run.
  mkdir -p "$_p6/bin" "$_p6/projects/app" "$_p6/certs/example.com"
  printf '%s\n' '#!/bin/sh' 'exit 1' > "$_p6/bin/docker"
  chmod 755 "$_p6/bin/docker"
  printf '%s\n' '#!/bin/sh' "echo called > '$_p6/ensure-called'" 'exit 0' > "$_p6/ensure.sh"
  chmod 755 "$_p6/ensure.sh"
  printf '%s\n' 'DOMAIN_NAME=example.com' > "$_p6/projects/app/.env"
  touch "$_p6/certs/example.com/fullchain.pem" "$_p6/certs/example.com/privkey.pem"
  if PATH="$_p6/bin:$PATH" \
      BATON_BASE_DIR="$ROOT" \
      BATON_PROJECTS_ROOT="$_p6/projects" \
      BATON_CERT_ROOT="$_p6/certs" \
      BATON_ENSURE_CERTS="$_p6/ensure.sh" \
      sh "$ROOT/scripts/tools/ssl/force-reissue-certs.sh" app >"$_p6/out" 2>"$_p6/err"
  then
    fail "phase6: force-reissue succeeded while certificate files remained"
  fi
  if [ -e "$_p6/ensure-called" ]; then
    fail "phase6: force-reissue called ensure-certs after a failed delete"
  fi
  if grep -q 'Done\.' "$_p6/out"; then
    fail "phase6: force-reissue printed Done after a failed delete"
  fi
  if ! grep -q 'certificate files still exist' "$_p6/err"; then
    fail "phase6: force-reissue did not report the leftover pems"
  fi
  ok "phase6: failed delete is not a reissue"

  rm -rf "$_p6"
}

phase6
