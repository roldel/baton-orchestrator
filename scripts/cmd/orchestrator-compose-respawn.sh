# Optionally implement log stats snapshot before container logs get reset and lost upon container rebuild

docker compose -f /opt/baton-orchestrator/orchestrator/docker-compose.yml down
docker compose -f /opt/baton-orchestrator/orchestrator/docker-compose.yml up -d --build --force-recreate