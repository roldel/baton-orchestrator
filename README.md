# 🪄 Baton Orchestrator

> **Every orchestra needs a baton — so does your VPS.**  
> Deploy, manage, and scale **Docker Compose projects** on your VPS with **minimal overhead**, **optimized resources**, and **maximum control**.

---

## 🚀 Overview

**Baton Orchestrator** is a lightweight, self-hosted orchestration toolkit designed for developers and sysadmins who want to:

- Deploy and manage multiple **Docker Compose projects** on a single VPS  
- Automatically handle **NGINX reverse proxy**, **Let's Encrypt SSL certificates**, and **network isolation**
- Use **plain shell scripts** for full transparency and easy debugging
- Run on **Alpine Linux**, but portable across most POSIX environments

It aims to bring automation and order to VPS deployments — without the complexity of Kubernetes or external orchestration layers.

---

## 🧩 Features

- 🧠 **Declarative project structure** (`projects/<name>`)
- ⚙️ **One-command deployment**: `./scripts/cmd/deploy.sh <project>`
- 🔐 **Auto SSL issuance & renewal** via `certbot`
- 🧱 **Modular shell-based tooling** (no Python/Go daemon overhead)
- 🔄 **Webhook-ready** for Git auto-redeploy
- 🌍 **NGINX ingress orchestration** with automatic config generation
- 🧪 **POSIX shell test suite** (`/tests`) for continuous validation

---

## 🧰 Installation

### 1️⃣ Clone the repository

```bash
git clone https://github.com/roldel/baton-orchestrator.git /opt/baton-orchestrator
cd /opt/baton-orchestrator
```

### 2️⃣ Run setup (as root)

This installs dependencies, prepares the file structure, creates the internal Docker network, and launches the base NGINX service.

```bash
./scripts/setup.sh
```

Upon success, you’ll see:
```
Setup complete!
   Nginx is running
   Certbot will start on-demand during first deploy
   Run: ./scripts/cmd/deploy.sh <project-name>
```

---

## 🧱 Directory Structure

```
.
├── orchestrator/                # Core stack: nginx, certbot, webhook
│   ├── docker-compose.yml
│   ├── nginx/
│   ├── webhook/
│   └── data/
├── projects/                    # Your deployable projects
│   └── demo-website/
│       ├── .env
│       ├── server.conf
│       └── template-docker-compose.yml
├── scripts/                     # Baton CLI tools
│   ├── cmd/                     # Commands (deploy, stand-down, cleanup)
│   ├── tools/                   # Low-level modules
│   └── setup.sh
└── tests/                       # Shell-based test suite
```

---

## 🪄 Usage

### Deploy a project

```bash
./scripts/cmd/deploy.sh <project-name>
```

This command:

1. Validates your project structure and environment (`.env`, `server.conf`, and compose file)
2. Renders your NGINX server configuration  
3. Brings up containers (`docker compose up -d`)
4. Checks or issues SSL certificates via `certbot`
5. Reloads the orchestrator’s NGINX with the new configuration

---

### Stand down a project

```bash
./scripts/cmd/stand-down.sh <project-name>
```

Removes the project’s NGINX configuration and stops its Docker Compose stack  
(SSL certificates remain on disk).

---

### Full cleanup (irreversible)

```bash
./scripts/cleanup.sh
```

Stops services, removes configurations, shared files, and optionally deletes the repo.  
⚠️ **Use only when resetting your VPS.**

---

## 🌐 Project Template

Example `projects/demo-website/.env`:
```ini
DOMAIN_NAME=example.com
DOMAIN_ADMIN_EMAIL=admin@example.com
DOCKER_NETWORK_SERVICE_ALIAS=myapp-service
APP_PORT=8000
DOMAIN_ALIASES=www.example.com,api.example.com
```

To create your own project:
1. Copy `projects/demo-website/` → `projects/yourproject/`
2. Update `.env`, `server.conf`, and `template-docker-compose.yml`
3. Run `./scripts/cmd/deploy.sh yourproject`

---

## 🧪 Testing

Baton Orchestrator includes a **zero-dependency** POSIX test framework.

Run all tests:
```bash
./tests/run-test.sh
```

Example output:
```
🔍 Running all test scripts in ./tests (recursively)
▶️  Running: ./tests/success.sh
✅ ./tests/success.sh PASSED

📊 Total tests run: 1
✅ Passed: 1
❌ Failed: 0
🎉 All tests passed!
```

See [`tests/TEST-ARCHITECTURE.md`](tests/TEST-ARCHITECTURE.md) for details.

---

## 🧠 Architecture Notes

- Each project runs its own Docker Compose stack.
- NGINX (in `orchestrator/nginx`) serves as the **central ingress** for all projects.
- Certificates are managed under:
  ```
  orchestrator/data/certs/
  ```
- Shared static/media files are exposed under `/shared-files/`.
- All scripts are written for **POSIX-compliant shells**, ensuring portability and transparency.

---

## 🧰 Commands Summary

| Command | Description |
|----------|-------------|
| `./scripts/setup.sh` | Initialize orchestrator (Alpine/Linux VPS) |
| `./scripts/cmd/deploy.sh <project>` | Deploy or update project |
| `./scripts/cmd/stand-down.sh <project>` | Disable project (keeps SSL) |
| `./scripts/cleanup.sh` | Remove orchestrator and all configs |

---

## 🧩 Coming Next

- 🔁 Webhook-triggered CI/CD auto-deploy  
- 🕒 Automatic SSL renewal  
- 🧰 Expanded `baton` CLI command set  
- 🩺 Health and uptime monitoring integration  

---