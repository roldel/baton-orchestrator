#!/bin/sh
# Load a .env file (KEY=VALUE lines; supports quoted values) into the environment.
# Usage: . "$SCRIPT_DIR/tools/load-dotenv.sh"; load_dotenv "/path/to/.env"
set -eu

load_dotenv() {
  dotenv_file="$1"
  [ -f "$dotenv_file" ] || { echo "ERROR: .env not found at $dotenv_file" >&2; return 1; }

  # parse simple KEY=VALUE lines (ignore comments/blank)
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    key="${line%%=*}"
    val="${line#*=}"
    # trim spaces
    key=$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    val=$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # strip optional surrounding quotes
    case "$val" in
      \"*\") val=${val#\"}; val=${val%\"} ;;
      \'*\') val=${val#\'}; val=${val%\'} ;;
    esac
    # export
    # shellcheck disable=SC2163
    export "$key=$val"
  done < "$dotenv_file"

  # post-process / normalize
  : "${DOMAIN_NAME:?DOMAIN_NAME is required in .env}"
  : "${DOCKER_NETWORK_SERVICE_ALIAS:?DOCKER_NETWORK_SERVICE_ALIAS is required in .env}"
  : "${SERVER_APP_PORT:?SERVER_APP_PORT is required in .env}"

  # Map required runtime vars
  export MAIN_DOMAIN_NAME="$DOMAIN_NAME"
  export APP_PORT="$SERVER_APP_PORT"

  # Normalize aliases: comma or space-separated → single-space-separated
  if [ -n "${DOMAIN_ALIASES:-}" ]; then
    DOMAIN_ALIASES="$(printf '%s' "$DOMAIN_ALIASES" | tr ',' ' ' | tr -s ' ')"
    export DOMAIN_ALIASES
  else
    export DOMAIN_ALIASES=""
  fi
}
