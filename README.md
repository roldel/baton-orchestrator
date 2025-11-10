# Baton Orchestrator

## Every orchestra needs a baton, so does your VPS

### Deploy, manage, and scale Docker compose projects on your VPS with minimal overhead, optimized resources, and maximum control



```sh

# Clone the baton-orchestrator repository
echo "Cloning baton-orchestrator repository..."
git clone https://github.com/roldel/baton-orchestrator.git /opt/baton-orchestrator || {
    echo "Error: Failed to clone the repository."
    exit 1
}

# Navigate to the project directory
cd /opt/baton-orchestrator || {
    echo "Error: Failed to enter /opt/baton-orchestrator."
    exit 1
}

# Run the setup script
echo "Running setup script..."
./scripts/setup.sh

```

Deploy a project :

```sh

./scripts/cmd/deploy.sh <project-name>


```