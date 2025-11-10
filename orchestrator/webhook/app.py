# webhook/app.py
from __future__ import annotations

import os
import json
import hmac
import hashlib
from datetime import datetime
from typing import Dict, Optional

from flask import Flask, request, abort
from dotenv import dotenv_values

app = Flask(__name__)

# -----------------------------------------------------------------------------
# Global config (overridable via environment variables)
# -----------------------------------------------------------------------------
WEBHOOK_PROJECTS_DIR = os.environ.get(
    "WEBHOOK_PROJECTS_DIR",
    os.path.join(os.path.dirname(__file__), "projects"),
)

# Where task files are written; map this path to host via docker-compose
SIGNAL_TO_HOST_DIR = os.environ.get(
    "SIGNAL_TO_HOST_DIR",
    "/webhook-redeploy-instruct"
)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
def load_project_env(project_dir: str) -> Dict[str, str]:
    """Load environment variables from <project_dir>/.env; return {} if missing."""
    env_path = os.path.join(project_dir, ".env")
    if os.path.exists(env_path):
        return dotenv_values(env_path) or {}
    return {}

def verify_github_signature(payload: bytes, secret: str, signature_header: Optional[str]) -> bool:
    """
    Verify GitHub-style HMAC SHA-256 signature:
      X-Hub-Signature-256: "sha256=<hex>"
    """
    if not secret or not signature_header or not signature_header.startswith("sha256="):
        return False
    provided_hex = signature_header.split("=", 1)[1].strip()
    digest_hex = hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(provided_hex, digest_hex)

def extract_branch(payload_json: dict) -> str:
    """Extract branch name from payload (supports GitHub and GitLab style refs)."""
    ref = payload_json.get("ref")
    if isinstance(ref, str) and ref.startswith("refs/heads/"):
        return ref.split("/", 2)[-1]
    return ""

def extract_commit_messages(payload_json: dict) -> str:
    """Collect commit messages from a typical GitHub push payload."""
    messages = []
    head_commit = payload_json.get("head_commit") or {}
    msg = head_commit.get("message")
    if isinstance(msg, str) and msg.strip():
        messages.append(msg.strip())

    commits = payload_json.get("commits") or []
    if isinstance(commits, list):
        for c in commits:
            m = (c or {}).get("message")
            if isinstance(m, str) and m.strip():
                messages.append(m.strip())

    return "\n".join(messages)

def yes_no(value: Optional[str], default: str = "NO") -> str:
    v = (value or "").strip().upper()
    return v if v in ("YES", "NO") else default

def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)

def write_task_file(
    project_name: str,
    repo_location: str,
    docker_restart_required: str,
    ci_pipeline_location: Optional[str],
    custom_redeploy_script_location: Optional[str],
) -> str:
    """Write key/value directives into a .baton file in SIGNAL_TO_HOST_DIR."""
    ensure_dir(SIGNAL_TO_HOST_DIR)
    ts = datetime.now().strftime("%Y%m%d%H%M%S%f")
    filename = f"task_{project_name}_{ts}.baton"
    path = os.path.join(SIGNAL_TO_HOST_DIR, filename)

    lines = [
        f"REPO_LOCATION={repo_location}",
        f"DOCKER_COMPOSE_RESTART_REQUIRED={docker_restart_required}",
    ]

    if ci_pipeline_location:
        lines.append(f"CI_PIPELINE_LOCATION={ci_pipeline_location}")
    if custom_redeploy_script_location:
        lines.append(f"CUSTOM_REDEPLOY_SCRIPT_LOCATION={custom_redeploy_script_location}")

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    return path

# -----------------------------------------------------------------------------
# Routes
# -----------------------------------------------------------------------------
@app.get("/health")
def health():
    return "OK", 200

@app.post("/webhook/<project_id>")
def webhook(project_id: str):
    """
    Identify project by directory name under WEBHOOK_PROJECTS_DIR,
    verify signature, ensure push is for TARGET_BRANCH (default 'main'),
    populate a task file with deployment parameters, and save to SIGNAL_TO_HOST_DIR.
    """
    payload_bytes = request.get_data(cache=False)
    signature = request.headers.get("X-Hub-Signature-256", "").strip()

    # 1) Locate project directory and .env
    project_dir = os.path.join(WEBHOOK_PROJECTS_DIR, project_id)
    if not (os.path.isdir(project_dir) and os.path.exists(os.path.join(project_dir, ".env"))):
        app.logger.warning("Project '%s' not found or missing .env; dropping.", project_id)
        abort(404)

    env = load_project_env(project_dir)

    # Required variables
    secret = (env.get("PAYLOAD_SIGNATURE") or "").strip()
    repo_location = (env.get("REPO_LOCATION") or "").strip()

    if not secret:
        app.logger.error("Project '%s' missing PAYLOAD_SIGNATURE.", project_id)
        abort(500)
    if not repo_location:
        app.logger.error("Project '%s' missing mandatory REPO_LOCATION.", project_id)
        abort(500)

    # 2) Verify signature
    if not verify_github_signature(payload_bytes, secret, signature):
        app.logger.warning("Signature verification failed for project '%s'.", project_id)
        abort(403)

    # 3) Parse payload JSON
    try:
        payload_json = json.loads(payload_bytes.decode("utf-8", "replace"))
    except json.JSONDecodeError:
        app.logger.warning("Invalid JSON payload for project '%s'.", project_id)
        abort(400)

    # 4) Ensure push is to main (or configured branch)
    target_branch = (env.get("TARGET_BRANCH") or "main").strip()
    branch = extract_branch(payload_json)
    if not branch:
        app.logger.warning("Could not determine branch in payload for project '%s'.", project_id)
        abort(400)

    if branch != target_branch:
        app.logger.info(
            "Ignoring push for branch '%s' (target '%s') in project '%s'.",
            branch, target_branch, project_id
        )
        return {"status": "ignored", "reason": "non-target-branch", "branch": branch}, 202

    # 5) Determine Docker restart
    docker_restart_required = yes_no(env.get("DOCKER_COMPOSE_RESTART_REQUIRED"), "NO")
    trigger = (env.get("COMMIT_DOCKER_COMPOSE_RESTART_TRIGGER") or "").strip()

    if docker_restart_required == "NO" and trigger:
        if trigger in extract_commit_messages(payload_json):
            docker_restart_required = "YES"
            app.logger.info("Commit trigger '%s' found → restart required", trigger)

    # 6) Optional fields
    ci_pipeline_location = (
        env.get("CI_PIPELINE_LOCATION") or env.get("CI_PEPLINE_LOCATION") or ""
    ).strip()
    custom_redeploy_script_location = (env.get("CUSTOM_REDEPLOY_SCRIPT_LOCATION") or "").strip()

    # 7) Write task file
    try:
        path = write_task_file(
            project_name=project_id,
            repo_location=repo_location,
            docker_restart_required=docker_restart_required,
            ci_pipeline_location=ci_pipeline_location,
            custom_redeploy_script_location=custom_redeploy_script_location,
        )
    except Exception as e:
        app.logger.exception("Failed to write task file for project '%s': %s", project_id, e)
        abort(500)

    app.logger.info("Task file created for project '%s': %s", project_id, path)
    return {"status": "queued", "project": project_id, "task": os.path.basename(path)}, 202

# -----------------------------------------------------------------------------
# Local dev entrypoint
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    os.makedirs(WEBHOOK_PROJECTS_DIR, exist_ok=True)
    os.makedirs(SIGNAL_TO_HOST_DIR, exist_ok=True)
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")))
