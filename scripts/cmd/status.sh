#!/bin/sh
# scripts/cmd/status.sh
# Overview of all Baton-managed projects under /srv/projects.
#
# For each project, reports:
#   - Host         (DOMAIN_NAME; aliases stay in the project .env)
#   - Mode         (dynamic / static)
#   - Site live    (SSL cert present + nginx config installed)
#   - Containers   (dynamic only: running / stopped / absent)
#   - Webhook      (active / inactive)
#
# Usage:
#   ./scripts/cmd/status.sh              # all projects
#   ./scripts/cmd/status.sh <project>    # single project

set -eu

BASE_DIR="${BATON_BASE_DIR:-/opt/baton-orchestrator}"
PROJECTS_ROOT="${BATON_PROJECTS_ROOT:-/srv/projects}"
NGINX_CONF_DIR="$BASE_DIR/orchestrator/nginx/conf.d"
WEBHOOKS_DIR="/srv/baton-orchestrator/webhooks.d"
CERT_BASE="/etc/letsencrypt/live"
COMPOSE_CMD="${BATON_COMPOSE_CMD:-$BASE_DIR/scripts/tools/helpers/compose-cmd.sh}"
RESOLVE_HELPER="$BASE_DIR/scripts/tools/helpers/resolve-compose-files.sh"
STATUS_RC=0

# --- Colour / formatting helpers (degrade gracefully if no tty) ---
if [ -t 1 ]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    BOLD=''; GREEN=''; RED=''; YELLOW=''; CYAN=''; RESET=''
fi

ok()   { printf "${GREEN}%-12s${RESET}" "$1"; }
warn() { printf "${YELLOW}%-12s${RESET}" "$1"; }
fail() { printf "${RED}%-12s${RESET}" "$1"; }
info() { printf "${CYAN}%-12s${RESET}" "$1"; }

# --- Resolve project list ---
# Built via positional params, not a space-joined string: a project directory
# name containing a space would otherwise be word-split by `for X in $LIST`
# and silently mishandled.
if [ $# -ge 1 ]; then
    PROJECT_ARG="$1"
    # A project name is one path segment under PROJECTS_ROOT.
    case "$PROJECT_ARG" in
        ''|.|..)
            echo "ERROR: invalid project name: '$PROJECT_ARG'" >&2
            exit 1
            ;;
        */*)
            echo "ERROR: project name cannot contain '/': '$PROJECT_ARG'" >&2
            exit 1
            ;;
    esac
    if [ ! -d "$PROJECTS_ROOT/$PROJECT_ARG" ]; then
        echo "ERROR: Project not found: $PROJECTS_ROOT/$PROJECT_ARG" >&2
        exit 1
    fi
    set -- "$PROJECT_ARG"
else
    if [ ! -d "$PROJECTS_ROOT" ] || [ -z "$(ls -A "$PROJECTS_ROOT" 2>/dev/null)" ]; then
        echo "No projects found under $PROJECTS_ROOT"
        exit 0
    fi
    set --
    for _entry in "$PROJECTS_ROOT"/*; do
        [ -d "$_entry" ] || continue
        set -- "$@" "${_entry##*/}"
    done
fi

# --- Header ---
# Width: 20+1+32+1+10+1+12+1+14+1+12 = 105
printf "\n${BOLD}%-20s %-32s %-10s %-12s %-14s %-12s${RESET}\n" \
    "PROJECT" "HOST" "MODE" "SITE" "CONTAINERS" "WEBHOOK"
printf '%0.s─' $(seq 1 105); printf '\n'

# --- Per-project loop ---
for PROJECT in "$@"; do
    PROJECT_DIR="$PROJECTS_ROOT/$PROJECT"
    [ -d "$PROJECT_DIR" ] || continue

    _st_ps=0
    _st_run=""
    _st_stop=""
    _st_err=""

    ENV_FILE="$PROJECT_DIR/.env"

    # Reset all .env-sourced vars before each iteration to prevent bleed
    STATIC_SITE="no"
    DOMAIN_NAME=""

    # Read STATIC_SITE in a subshell. DOMAIN_NAME comes from compute-site-key.sh.
    if [ -f "$ENV_FILE" ]; then
        STATIC_SITE="$(
            set +eu
            . "$BASE_DIR/scripts/tools/helpers/load-env-safe.sh"
            if load_env_safe "$ENV_FILE"; then
                printf '%s' "${STATIC_SITE:-no}"
            fi
        )"
        [ -n "$STATIC_SITE" ] || STATIC_SITE="no"
        DOMAIN_NAME="$(sh "$BASE_DIR/scripts/tools/helpers/compute-site-key.sh" "$PROJECT" 2>/dev/null)" || DOMAIN_NAME=""
    fi

    # --- HOST column ---
    # Plain text, padded here. The colour helpers pad to 12 columns and would
    # clip a hostname. A name longer than 32 is printed in full.
    if [ -n "$DOMAIN_NAME" ]; then
        HOST_COL="$(printf '%-32s' "$DOMAIN_NAME")"
    else
        HOST_COL="$(printf '%b%-26s' "${YELLOW}(none)${RESET}" '')"
    fi

    # --- MODE column ---
    case "$STATIC_SITE" in
        yes) MODE_COL="$(info 'static')" ;;
        no)  MODE_COL="$(info 'dynamic')" ;;
        *)   MODE_COL="$(warn 'unknown')" ;;
    esac

    # --- SITE column (cert + nginx config) ---
    CERT_OK=0
    CONF_OK=0
    [ -f "$CERT_BASE/${DOMAIN_NAME}/fullchain.pem" ] && CERT_OK=1
    [ -f "$NGINX_CONF_DIR/${DOMAIN_NAME}.conf" ]     && CONF_OK=1

    if [ "$CERT_OK" -eq 1 ] && [ "$CONF_OK" -eq 1 ]; then
        SITE_COL="$(ok 'live')"
    elif [ "$CERT_OK" -eq 0 ] && [ "$CONF_OK" -eq 0 ]; then
        SITE_COL="$(fail 'down')"
    elif [ "$CERT_OK" -eq 0 ]; then
        SITE_COL="$(warn 'no cert')"
    else
        SITE_COL="$(warn 'no nginx')"
    fi

    # --- CONTAINERS column (dynamic only) ---
    if [ "$STATIC_SITE" = "yes" ]; then
        CONTAINERS_COL="$(info 'n/a')"
    elif ! command -v docker >/dev/null 2>&1; then
        CONTAINERS_COL="$(warn 'no docker')"
    else
        # Resolve the compose file list once and pass it to both `ps` calls
        # below via --file, instead of letting compose-cmd.sh re-run
        # resolve-compose-files.sh (re-parsing .env) on every invocation.
        COMPOSE_FILES="$(sh "$RESOLVE_HELPER" "$PROJECT_DIR" 2>/dev/null)" || COMPOSE_FILES=""
        if [ -z "$COMPOSE_FILES" ]; then
            CONTAINERS_COL="$(warn 'no compose')"
        else
            set --
            while IFS= read -r _cf || [ -n "$_cf" ]; do
                [ -n "$_cf" ] || continue
                set -- "$@" --file "$_cf"
            done <<EOF
$COMPOSE_FILES
EOF
            set -- "$@" --

            # A failed ps is not an empty project. Its message is printed
            # once, under the row. A successful ps adds nothing under the row.
            _st_run=$(mktemp)
            _st_stop=$(mktemp)
            _st_err=$(mktemp)
            _st_ps=0
            if ! sh "$COMPOSE_CMD" "$PROJECT_DIR" "$@" ps --status running \
                    --format '{{.Name}}' >"$_st_run" 2>"$_st_err"; then
                _st_ps=1
            elif ! sh "$COMPOSE_CMD" "$PROJECT_DIR" "$@" ps --status exited --status stopped \
                    --format '{{.Name}}' >"$_st_stop" 2>"$_st_err"; then
                _st_ps=1
            fi
            if [ "$_st_ps" -ne 0 ]; then
                CONTAINERS_COL="$(fail 'error')"
                STATUS_RC=1
            else
                RUNNING="$(wc -l < "$_st_run" | tr -d ' ')"
                STOPPED="$(wc -l < "$_st_stop" | tr -d ' ')"
                TOTAL=$((RUNNING + STOPPED))

                if [ "$TOTAL" -eq 0 ]; then
                    CONTAINERS_COL="$(warn 'absent')"
                elif [ "$STOPPED" -gt 0 ] && [ "$RUNNING" -eq 0 ]; then
                    CONTAINERS_COL="$(fail "stopped($TOTAL)")"
                elif [ "$STOPPED" -gt 0 ]; then
                    CONTAINERS_COL="$(warn "${RUNNING}↑ ${STOPPED}↓")"
                else
                    CONTAINERS_COL="$(ok "${RUNNING} running")"
                fi
            fi
        fi
    fi

    # --- WEBHOOK column ---
    WEBHOOK_CONF="$WEBHOOKS_DIR/${DOMAIN_NAME}-webhook.conf"
    if [ -f "$WEBHOOK_CONF" ]; then
        WEBHOOK_COL="$(ok 'active')"
    else
        WEBHOOK_COL="$(warn 'inactive')"
    fi

    # --- Print row ---
    printf "%-20s %s %b %-2s %b %-2s %b %-2s %b\n" \
        "$PROJECT" \
        "$HOST_COL" \
        "$MODE_COL" "" \
        "$SITE_COL" "" \
        "$CONTAINERS_COL" "" \
        "$WEBHOOK_COL"
    if [ "$_st_ps" -ne 0 ] && [ -n "$_st_err" ] && [ -s "$_st_err" ]; then
        cat "$_st_err"
    fi
    if [ -n "$_st_run" ]; then
        rm -f "$_st_run" "$_st_stop" "$_st_err"
    fi
done

printf '%0.s─' $(seq 1 105); printf '\n\n'
exit "$STATUS_RC"
