#!/bin/sh
# Load .env and normalize variables
set -eu

load_dotenv() {
  dotenv_file="$1"
  [ -f "$dotenv_file" ] || { echo "ERROR: .env not found at $dotenv_file" >&2; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    key=$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    val=$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$val" in \"*\") val=${val#\"}; val=${val%\"} ;; \'*\') val=${val#\'}; val=${val%\'} ;; esac
    export "$key=$val"
  done < "$dotenv_file"

  : "${DOMAIN_NAME:?DOMAIN_NAME is required in .env}"
  : "${DOCKER_NETWORK_SERVICE_ALIAS:?DOCKER_NETWORK_SERVICE_ALIAS is required in .env}"
  : "${APP_PORT:?APP_PORT is required in .env}"

  # Canonical names
  export APP_PORT="$SERVER_APP_PORT"

  # Back-compat (prefer DOMAIN_NAME everywhere; MAIN_DOMAIN_NAME is a mirror)
  export MAIN_DOMAIN_NAME="$DOMAIN_NAME"

  # Normalize aliases to space-separated
  if [ -n "${DOMAIN_ALIASES:-}" ]; then
    DOMAIN_ALIASES="$(printf '%s' "$DOMAIN_ALIASES" | tr ',' ' ' | tr -s ' ')"
    export DOMAIN_ALIASES
  else
    export DOMAIN_ALIASES=""
  fi
}