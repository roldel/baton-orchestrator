#!/bin/sh
# scripts/cmd/deploy.sh
set -eu

[ -n "${BASE_DIR:-}" ] || { echo "Run via 'baton deploy <project>'"; exit 1; }
. "$BASE_DIR/env-setup.sh"
. "$SCRIPT_DIR/tools/load-dotenv.sh"

proj="${1:-}"
[ -n "$proj" ] || { echo "Usage: baton deploy <project>"; exit 1; }

# Step 1: Validate project structure and .env
. "$SCRIPT_DIR/tools/validate-project.sh"
validate_project "$proj"

# Step 2: Load environment
env_file="$PROJECTS_DIR/$proj/.env"
load_dotenv "$env_file" >/dev/null

# Step 3: Render Caddy config
. "$SCRIPT_DIR/tools/render-caddy-conf.sh"
rendered=$(render_caddy_conf "$proj")

# Step 4: Stage config
. "$SCRIPT_DIR/tools/stage-config.sh"
tmp=$(stage_config "$rendered" "$DOMAIN_NAME")

# Step 5: Test Caddy config
. "$SCRIPT_DIR/tools/caddy-test.sh"
caddy_test "$tmp"

# Step 6: Commit config
. "$SCRIPT_DIR/tools/commit-config.sh"
commit_config "$tmp" "$DOMAIN_NAME"

# Step 7: Reload Caddy
echo "Reloading Caddy to apply new configuration..."
if docker exec ingress-caddy caddy reload --config /etc/caddy/Caddyfile; then
  echo "Successfully deployed and reloaded Caddy for $DOMAIN_NAME"
else
  echo "ERROR: Caddy reload failed. Check Caddy container logs for details:" >&2
  echo "  docker logs ingress-caddy" >&2
  exit 1
fi
