# orchestrator/webhook/utils.py

import os
import json
import hmac
import hashlib
import datetime
import tempfile
import uuid
import logging

from flask import abort

from envfile import HostConflict, find_project_by_host

logger = logging.getLogger(__name__)


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

    Filename is unique under burst load:
      task_<YYYYMMDD-HHMMSS>_<pid>_<uuid8>_<project>.baton
    The leading timestamp keeps lexicographic order ≈ enqueue order for the
    host worker; pid + uuid avoid same-second collisions.
    """
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    # Sanitize project for use in a filename (keep it readable; PROJECT= inside
    # the file is the source of truth for the real name).
    safe_project = "".join(
        c if (c.isalnum() or c in "-_.") else "_" for c in project
    ) or "project"
    task_filename = (
        f"task_{timestamp}_{os.getpid()}_{uuid.uuid4().hex[:8]}_{safe_project}.baton"
    )

    # Branch to deploy. The handler resets the working tree to
    # origin/<TARGET_BRANCH>, so this must be carried through explicitly —
    # otherwise the handler falls back to whatever branch the on-disk
    # checkout happens to point at. Mirrors the default used for the
    # branch filter in process_webhook_request.
    target_branch = env.get("TARGET_BRANCH") or "main"

    # REPO_LOCATION is now guaranteed upstream in process_webhook_request,
    # but we still guard defensively here.
    repo_location = env.get("REPO_LOCATION") or ""
    ci_pipeline_location = env.get("CI_PIPELINE_LOCATION") or ""
    custom_redeploy_script_location = env.get("CUSTOM_REDEPLOY_SCRIPT_LOCATION") or ""

    # The task file is read line-by-line. A newline inside a value would
    # inject another KEY=VALUE line. Reject that before writing.
    for key, value in (
        ("PROJECT", project),
        ("TARGET_BRANCH", target_branch),
        ("REPO_LOCATION", repo_location),
        ("DOCKER_COMPOSE_RESTART_REQUIRED", restart_required),
        ("CI_PIPELINE_LOCATION", ci_pipeline_location),
        ("CUSTOM_REDEPLOY_SCRIPT_LOCATION", custom_redeploy_script_location),
    ):
        if "\n" in str(value) or "\r" in str(value):
            raise ValueError(f"{key} must not contain a newline")

    # Create temp file in the same dir to allow atomic rename
    with tempfile.NamedTemporaryFile(
        mode="w", dir=signal_dir, delete=False
    ) as temp_file:
        temp_path = temp_file.name

        # Mandatory
        temp_file.write(f"PROJECT={project}\n")
        temp_file.write(f"TARGET_BRANCH={target_branch}\n")

        if repo_location:
            temp_file.write(f"REPO_LOCATION={repo_location}\n")

        # Docker compose restart decision
        temp_file.write(f"DOCKER_COMPOSE_RESTART_REQUIRED={restart_required}\n")

        # Optional CI pipeline
        if ci_pipeline_location:
            temp_file.write(f"CI_PIPELINE_LOCATION={ci_pipeline_location}\n")

        # Optional custom redeploy script
        if custom_redeploy_script_location:
            temp_file.write(
                f"CUSTOM_REDEPLOY_SCRIPT_LOCATION={custom_redeploy_script_location}\n"
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
    try:
        project, env = find_project_by_host(host, projects_root_dir)
    except HostConflict:
        abort(409, description="Host matches more than one project")
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
