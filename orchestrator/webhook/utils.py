# orchestrator/webhook/utils.py

import os
import json
import hmac
import hashlib
import datetime
import tempfile

from flask import abort
from dotenv import dotenv_values


def find_project_by_host(host, projects_dir):
    """
    Scans projects_dir for .env files and matches the Host against
    DOMAIN_NAME or DOMAIN_ALIASES.

    Returns (project_name, env_dict) or (None, None).
    """
    # Iterate over items in the mounted /app/projects directory
    # (which is /srv/projects on the host via bind mount)
    for project_name in os.listdir(projects_dir):
        # Construct the full path to the potential project directory
        project_path = os.path.join(projects_dir, project_name)

        # Ensure it's an actual directory before looking for an .env file
        if not os.path.isdir(project_path):
            continue

        env_path = os.path.join(project_path, ".env")
        if os.path.isfile(env_path):
            # Load the .env values from the found file
            env = dotenv_values(env_path)

            domain_name = env.get("DOMAIN_NAME", "").lower()
            if not domain_name:
                # Skip projects without a defined DOMAIN_NAME
                continue

            aliases = env.get("DOMAIN_ALIASES", "")
            # Normalize aliases: comma or space separated → list
            alias_list = [d.strip().lower() for d in aliases.replace(",", " ").split() if d.strip()]
            all_domains = [domain_name] + alias_list

            # Check if the incoming Host header matches any of the domains
            if host in all_domains:
                return project_name, env

    # No matching project found
    return None, None


def verify_signature(secret, body, signature_header):
    """
    Verifies GitHub's HMAC SHA256 signature.
    """
    if not signature_header:
        return False

    expected_sig = "sha256=" + hmac.new(
        secret.encode("utf-8"),
        body,
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(signature_header, expected_sig)


def should_restart_docker(commits, trigger_token):
    """
    Checks if any commit message contains the trigger token
    (e.g., '[restart-compose]').
    """
    if not trigger_token:
        return False

    for commit in commits:
        message = commit.get("message", "")
        if trigger_token in message:
            return True

    return False


def create_task_file(project, env, signal_dir, restart_required):
    """
    Atomically creates a task_*.baton file with shell-sourceable key=value lines.
    """
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    task_filename = f"task_{timestamp}_{project}.baton"

    # Create temp file in the same dir to allow atomic rename
    with tempfile.NamedTemporaryFile(
        mode="w", dir=signal_dir, delete=False
    ) as temp_file:
        temp_path = temp_file.name

        # Mandatory
        temp_file.write(f"PROJECT={project}\n")

        # REPO_LOCATION is now guaranteed upstream in process_webhook_request,
        # but we still guard defensively here.
        if "REPO_LOCATION" in env and env["REPO_LOCATION"]:
            temp_file.write(f'REPO_LOCATION={env["REPO_LOCATION"]}\n')

        # Docker compose restart decision
        temp_file.write(f"DOCKER_COMPOSE_RESTART_REQUIRED={restart_required}\n")

        # Optional CI pipeline
        if "CI_PIPELINE_LOCATION" in env and env["CI_PIPELINE_LOCATION"]:
            temp_file.write(
                f'CI_PIPELINE_LOCATION={env["CI_PIPELINE_LOCATION"]}\n'
            )

        # Optional custom redeploy script
        if (
            "CUSTOM_REDEPLOY_SCRIPT_LOCATION" in env
            and env["CUSTOM_REDEPLOY_SCRIPT_LOCATION"]
        ):
            temp_file.write(
                "CUSTOM_REDEPLOY_SCRIPT_LOCATION="
                f'{env["CUSTOM_REDEPLOY_SCRIPT_LOCATION"]}\n'
            )

    # Atomic rename
    final_path = os.path.join(signal_dir, task_filename)
    os.rename(temp_path, final_path)
    return final_path


def process_webhook_request(request, projects_root_dir, signal_to_host_dir):
    """
    Main webhook processing logic.
    Handles validation, verification, filtering, and task creation.

    projects_root_dir comes from app.py (WEBHOOK_PROJECTS_DIR) and points to
    the root of all projects inside the container (e.g. /app/projects).
    """
    # Step 1: Extract Host header
    host = request.headers.get("Host", "").split(":", 1)[0].lower()
    if not host:
        abort(400, description="Missing Host header")

    # Step 2: Find project by domain using the provided projects_root_dir
    project, env = find_project_by_host(host, projects_root_dir)
    if not project:
        abort(403, description="No matching project for this domain")

    # Step 3: Ensure REPO_LOCATION is always set
    #
    # Strategy:
    # - If REPO_LOCATION exists in .env, use it as-is.
    # - Otherwise, default to <projects_root_dir>/<project> which maps to
    #   /srv/projects/<project> on the host (via the bind mount).
    env_with_repo = dict(env)  # copy to avoid mutating the original mapping
    if not env_with_repo.get("REPO_LOCATION"):
        host_projects_root_dir = "/srv/projects"
        env_with_repo["REPO_LOCATION"] = os.path.join(host_projects_root_dir, project)

    # Step 4: Verify signature
    signature_header = request.headers.get("X-Hub-Signature-256")
    body = request.get_data()
    secret = env_with_repo.get("PAYLOAD_SIGNATURE")
    if not secret:
        abort(500, description="Missing PAYLOAD_SIGNATURE in project config")
    if not verify_signature(secret, body, signature_header):
        abort(403, description="Invalid signature")

    # Step 5: Check event type
    event = request.headers.get("X-GitHub-Event")
    if event != "push":
        return "Ignored non-push event", 200

    # Step 6: Parse JSON
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        abort(400, description="Invalid JSON")

    # Step 7: Extract ref
    ref = payload.get("ref")

    # Step 8: Check target branch
    target_branch = env_with_repo.get("TARGET_BRANCH", "main")
    if ref != f"refs/heads/{target_branch}":
        return "Ignored: Wrong branch", 200

    # Step 9: Check commit trigger (optional)
    commits = payload.get("commits", [])
    trigger_token = env_with_repo.get("COMMIT_DOCKER_COMPOSE_RESTART_TRIGGER")
    restart_required = (
        "YES"
        if should_restart_docker(commits, trigger_token)
        else env_with_repo.get("DOCKER_COMPOSE_RESTART_REQUIRED", "NO")
    )

    # Step 10-11: Create task file
    try:
        task_path = create_task_file(
            project, env_with_repo, signal_to_host_dir, restart_required
        )
    except Exception as e:
        abort(500, description=f"Failed to create task file: {str(e)}")

    # Step 12: Return immediately
    return "OK", 200

    # Step 13: Logging happens via Flask's logger; add app.logger calls if more needed
