# /home/x/Code/baton-orchestrator/scripts/manual/deploy.sh
#!/bin/sh
# Usage: ./scripts/manual/deploy.sh <project-name>
# Or from anywhere: sh scripts/manual/deploy.sh <project-name>
#
# Runs the full manual deployment pipeline:
#   1) initial validation
#   2) .env validation
#   3) render server.conf -> orchestrator/server-confs/<project>.conf
#   4) caddy config validate (inside container)
#   5) restart caddy to apply

set -eu

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "Usage: $0 <project-name>" >&2; exit 1; }

# Resolve repo root regardless of where this script is called from
THIS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$THIS_DIR/../.." && pwd)"
cd "$REPO_ROOT"

log() { printf "%s %s\n" "[deploy:$PROJECT]" "$*"; }

log "Starting manual deploy…"
log "Repo root: $REPO_ROOT"

# 1) sanity checks for project and required files
log "Step 1/5: initial validation"
sh "$REPO_ROOT/scripts/manual/initial-validation.sh" "$PROJECT"

# 2) check .env keys are present
log "Step 2/5: validate env"
sh "$REPO_ROOT/scripts/manual/validate-env.sh" "$PROJECT"

# 3) render server.conf for caddy
log "Step 3/5: render server.conf"
sh "$REPO_ROOT/scripts/manual/render-server-conf.sh" "$PROJECT"

# 4) validate rendered config inside the caddy container
log "Step 4/5: caddy conf check"
sh "$REPO_ROOT/scripts/manual/caddy-conf-check.sh" "$PROJECT"

# 5) apply by restarting caddy (admin API is disabled)
log "Step 5/5: caddy reload (container restart)"
sh "$REPO_ROOT/scripts/manual/caddy-reload.sh"

log "🎉 Manual deploy completed successfully."
