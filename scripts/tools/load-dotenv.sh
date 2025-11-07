#!/bin/sh
# scripts/tools/load-dotenv.sh
# Load .env and normalize variables
set -eu

load_dotenv() {
  dotenv_file="$1"
  [ -f "$dotenv_file" ] || { echo "ERROR: .env not found at $dotenv_file" >&2; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"
    val="${line#*=}"

    # Trim whitespace
    key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Strip surrounding quotes (single or double)
    val="$(printf '%s' "$val" | sed 's/^"\(.*\)\"$/\1/; s/^'\''\(.*\)'\''$/\1/')"

    export "$key=$val"
  done < "$dotenv_file"

  : "${DOMAIN_NAME:?DOMAIN_NAME is required in .env}"
  : "${DOCKER_NETWORK_SERVICE_ALIAS:?DOCKER_NETWORK_SERVICE_ALIAS is required in .env}"
  : "${APP_PORT:?APP_PORT is required in .env}"

  # Canonical names
  export APP_PORT="$APP_PORT"
  export MAIN_DOMAIN_NAME="$DOMAIN_NAME"

  # Normalize aliases: comma → space, dedupe
  if [ -n "${DOMAIN_ALIASES:-}" ]; then
    DOMAIN_ALIASES="$(printf '%s' "$DOMAIN_ALIASES" | tr ',' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')"
    export DOMAIN_ALIASES
  else
    export DOMAIN_ALIASES=""
  fi
}
