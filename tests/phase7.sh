# Phase 7 — static publish rejects escaping symlinks and sweeps old staging only.

phase7() {
  _p7=$(mktemp -d)
  . "$ROOT/scripts/tools/static/publish-lib.sh"

  _p7_norm=$(baton_collapse_path "/tmp/stage/../stage-evil")
  if [ "$_p7_norm" = "/tmp/stage" ] || [ "$_p7_norm" = "/tmp/stage/" ]; then
    fail "phase7: collapse treated a prefix sibling as the staging root ($_p7_norm)"
  fi
  case $_p7_norm in
    /tmp/stage|/tmp/stage/*)
      fail "phase7: collapsed sibling $_p7_norm matched /tmp/stage"
      ;;
  esac
  ok "phase7: collapse does not match a prefix sibling"

  mkdir -p "$_p7/staging"
  printf '%s\n' 'hi' > "$_p7/staging/index.html"
  ln -s /etc/passwd "$_p7/staging/secret"
  ln -s ./index.html "$_p7/staging/ok"
  if baton_reject_escaping_symlinks "$_p7/staging"; then
    fail "phase7: a symlink to /etc/passwd was accepted"
  fi
  if [ -e "$_p7/site" ] || [ -L "$_p7/site" ]; then
    fail "phase7: the escaping check created a site symlink"
  fi
  if [ ! -L "$_p7/staging/secret" ]; then
    fail "phase7: the escaping check removed the staging tree"
  fi
  ok "phase7: escaping symlink is rejected and unpublished"

  rm "$_p7/staging/secret"
  if ! baton_reject_escaping_symlinks "$_p7/staging"; then
    fail "phase7: a relative link inside the tree was rejected"
  fi
  ok "phase7: in-tree relative symlink passes"

  _p7_old=$(date -d '2 days ago' '+%Y%m%d-%H%M%S')
  _p7_new=$(date '+%Y%m%d-%H%M%S')
  mkdir -p "$_p7/releases/.staging-$_p7_old-00001" \
    "$_p7/releases/.staging-$_p7_new-00002" \
    "$_p7/releases/.staging-$_p7_old-00003"
  baton_sweep_staging "$_p7/releases" "$_p7/releases/.staging-$_p7_old-00003" \
    || fail "phase7: staging sweep failed"
  if [ -e "$_p7/releases/.staging-$_p7_old-00001" ]; then
    fail "phase7: old staging dir was kept"
  fi
  if [ ! -d "$_p7/releases/.staging-$_p7_new-00002" ]; then
    fail "phase7: fresh staging dir was removed"
  fi
  if [ ! -d "$_p7/releases/.staging-$_p7_old-00003" ]; then
    fail "phase7: sweep deleted the live target"
  fi
  ok "phase7: staging sweep keeps a fresh dir and the live target"

  ln -s "$_p7/releases/old" "$_p7/releases/site"
  baton_atomic_symlink "$_p7/releases/new" "$_p7/releases/site" \
    || fail "phase7: atomic symlink failed"
  if [ "$(readlink "$_p7/releases/site")" != "$_p7/releases/new" ]; then
    fail "phase7: atomic symlink did not replace the live link"
  fi
  ok "phase7: atomic symlink replaces the live link"

  rm -rf "$_p7"
}

phase7
