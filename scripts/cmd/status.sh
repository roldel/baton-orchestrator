#!/bin/sh
# scripts/cmd/status.sh
# Overview of all Baton-managed projects under /srv/projects.
#
# For each project, reports:
#   - Mode         (dynamic / static)
#   - Site live    (SSL cert present + nginx config installed)
#   - Containers   (dynamic only: running / stopped / absent)
#   - Webhook      (active / inactive)
#
# Usage:
#   ./scripts/cmd/status.sh              # all projects
#   ./scripts/cmd/status.sh <project>    # single project

set -eu

BASE_DIR="/opt/baton-orchestrator"
PROJECTS_ROOT="/srv/projects"
NGINX_CONF_DIR="$BASE_DIR/orchestrator/nginx/conf.d"
WEBHOOKS_DIR="/srv/baton-orchestrator/webhooks.d"
CERT_BASE="/etc/letsencrypt/live"
COMPOSE_HELPER="$BASE_DIR/scripts/tools/helpers/detect-compose-file.sh"

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
if [ $# -ge 1 ]; then
    PROJECTS="$1"
    if [ ! -d "$PROJECTS_ROOT/$PROJECTS" ]; then
        echo "ERROR: Project not found: $PROJECTS_ROOT/$PROJECTS" >&2
        exit 1
    fi
else
    if [ ! -d "$PROJECTS_ROOT" ] || [ -z "$(ls -A "$PROJECTS_ROOT" 2>/dev/null)" ]; then
        echo "No projects found under $PROJECTS_ROOT"
        exit 0
    fi
    PROJECTS="$(ls "$PROJECTS_ROOT")"
fi

# --- Header ---
printf "\n${BOLD}%-20s %-10s %-12s %-14s %-12s${RESET}\n" \
    "PROJECT" "MODE" "SITE" "CONTAINERS" "WEBHOOK"
printf '%0.s─' $(seq 1 72); printf '\n'

# --- Per-project loop ---
for PROJECT in $PROJECTS; do
    PROJECT_DIR="$PROJECTS_ROOT/$PROJECT"
    [ -d "$PROJECT_DIR" ] || continue

    ENV_FILE="$PROJECT_DIR/.env"

    # Reset all .env-sourced vars before each iteration to prevent bleed
    STATIC_SITE="no"
    DOMAIN_NAME=""

    if [ -f "$ENV_FILE" ]; then
        # shellcheck source=/dev/null
        . "$ENV_FILE"
        STATIC_SITE="${STATIC_SITE:-no}"
        DOMAIN_NAME="${DOMAIN_NAME:-}"
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
        COMPOSE_FILE="$(sh "$COMPOSE_HELPER" "$PROJECT_DIR" 2>/dev/null || true)"

        if [ -z "$COMPOSE_FILE" ]; then
            CONTAINERS_COL="$(warn 'no compose')"
        else
            # Use `docker compose ps` against the actual file — most reliable approach
            RUNNING="$(docker compose -f "$COMPOSE_FILE" ps --status running \
                           --format '{{.Name}}' 2>/dev/null | wc -l | tr -d ' ')"
            STOPPED="$(docker compose -f "$COMPOSE_FILE" ps --status exited --status stopped \
                           --format '{{.Name}}' 2>/dev/null | wc -l | tr -d ' ')"
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

    # --- WEBHOOK column ---
    WEBHOOK_CONF="$WEBHOOKS_DIR/${DOMAIN_NAME}-webhook.conf"
    if [ -f "$WEBHOOK_CONF" ]; then
        WEBHOOK_COL="$(ok 'active')"
    else
        WEBHOOK_COL="$(warn 'inactive')"
    fi

    # --- Print row ---
    printf "%-20s %b %-2s %b %-2s %b %-2s %b\n" \
        "$PROJECT" \
        "$MODE_COL" "" \
        "$SITE_COL" "" \
        "$CONTAINERS_COL" "" \
        "$WEBHOOK_COL"
done

printf '%0.s─' $(seq 1 72); printf '\n\n'
