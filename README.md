# Baton Orchestrator

## Every orchestra needs a baton, so does your VPS

### Deploy, manage, and scale Docker compose projects on your VPS with minimal overhead, optimized resources, and maximum control



```sh

git clone https://github.com/roldel/baton-orchestrator.git /opt/baton-orchestrator
cd /opt/baton-orchestrator
chmod +x scripts/*.sh scripts/cmd/*.sh scripts/tools/*.sh
./scripts/setup.sh
```


```sh
# Tempo fix before webhook implement
touch orchestrator/webhook/.env
docker compose -f orchestrator/docker-compose.yml up -d

baton deploy demo-website


```