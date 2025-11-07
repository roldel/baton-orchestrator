#!/bin/sh
# Usage: ./scripts/manual/validate-env.sh <project-name>
# Checks that mandatory variables exist in projects/<project>/.env
# and prints optional ones if present.

set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

ENV_PATH="projects/$PROJECT/.env"
echo "[validate-env] Checking $ENV_PATH"

if [ ! -f "$ENV_PATH" ]; then
  echo "ERROR: Missing .env at $ENV_PATH" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$ENV_PATH"

missing=0

check_var() {
  var="$1"
  val="$(eval echo "\${$var:-}")"
  if [ -z "$val" ]; then
    echo "ERROR: Missing or empty $var" >&2
    missing=1
  else
    echo "[validate-env] ✅ $var=$val"
  fi
}

show_if_present() {
  var="$1"
  val="$(eval echo "\${$var:-}")"
  if [ -n "$val" ]; then
    echo "[validate-env] ℹ️  $var=$val"
  else
    echo "[validate-env] (optional) $var not set"
  fi
}

echo "[validate-env] Checking mandatory vars..."
for v in DOMAIN_NAME DOCKER_NETWORK_SERVICE_ALIAS APP_PORT; do
  check_var "$v"
done

echo "[validate-env] Checking optional vars..."
for v in DOMAIN_ALIASES DOMAIN_ADMIN_EMAIL; do
  show_if_present "$v"
done

if [ "$missing" -ne 0 ]; then
  echo "[validate-env] ❌ Mandatory fields missing"
  exit 1
fi

echo "[validate-env] 🎉 All mandatory fields OK"
