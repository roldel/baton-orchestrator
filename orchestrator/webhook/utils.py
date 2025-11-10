# orchestrator/webhook/utils.py

import os
import re
from dotenv import dotenv_values
import hmac
import hashlib # Make sure hashlib is imported for sha256

def load_project_env(project_path):
    """
    Loads environment variables from a project's .env file.
    Returns a dictionary of key-value pairs.
    """
    env_file_path = os.path.join(project_path, '.env')
    if not os.path.exists(env_file_path):
        return {}
    
    return dotenv_values(env_file_path)

def find_matching_project(project_id, webhook_projects_dir):
    """
    Iterates through webhook projects to find one matching the project_id.
    Returns (project_name, project_env_dict) if found, otherwise (None, {}).
    """
    for project_name in os.listdir(webhook_projects_dir):
        project_path = os.path.join(webhook_projects_dir, project_name)
        if os.path.isdir(project_path):
            project_env = load_project_env(project_path)
            expected_webhook_url = project_env.get('WEBHOOK_URL', '')
            
            # Extract the last segment to match project_id
            expected_webhook_url_suffix = expected_webhook_url.split('/')[-1]

            if expected_webhook_url_suffix == project_id:
                return project_name, project_env
    return None, {}

def write_task_file(signal_dir, project_name, repo_location, docker_restart_required, ci_pipeline_location, custom_redeploy_script_location):
    """
    Writes a task file to the specified signal directory.
    """
    os.makedirs(signal_dir, exist_ok=True)
    
    from datetime import datetime
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S%f")
    task_filename = f"task_{project_name}_{timestamp}.baton"
    task_file_path = os.path.join(signal_dir, task_filename)

    task_content = [
        f"REPO_LOCATION={repo_location}",
        f"DOCKER_COMPOSE_RESTART_REQUIRED={docker_restart_required}"
    ]
    if ci_pipeline_location:
        task_content.append(f"CI_PEPLINE_LOCATION={ci_pipeline_location}")
    if custom_redeploy_script_location:
        task_content.append(f"CUSTOM_REDEPLOY_SCRIPT_LOCATION={custom_redeploy_script_location}")

    with open(task_file_path, 'w') as f:
        f.write("\n".join(task_content))
    
    return task_file_path

# --- MODIFIED VERIFY_SIGNATURE FUNCTION ---
def verify_signature(payload_body, secret_token, signature_header):
    """
    Verify that the payload was sent from GitHub (or compatible source)
    by validating its SHA256 HMAC signature.

    Args:
        payload_body: The raw body of the incoming request (bytes).
        secret_token: The shared secret configured for the webhook (string).
        signature_header: The value of the 'X-Hub-Signature-256' header (string).
    
    Returns:
        True if the signature is valid, False otherwise.
    """
    if not signature_header:
        print("Signature verification failed: x-hub-signature-256 header is missing.")
        return False

    try:
        # GitHub's signature header format is "sha256=<signature>"
        # We need to ensure we compare apples to apples.
        # The provided signature_header already has the "sha256=" prefix if it's from GitHub.
        # We need to compute our expected signature with the prefix as well.

        # Calculate the HMAC digest
        hash_object = hmac.new(secret_token.encode('utf-8'), msg=payload_body, digestmod=hashlib.sha256)
        expected_signature = "sha256=" + hash_object.hexdigest()
        
        # Securely compare the expected signature with the received one
        if hmac.compare_digest(expected_signature, signature_header):
            return True
        else:
            print("Signature verification failed: Request signatures didn't match.")
            return False
    except Exception as e:
        print(f"Signature verification failed due to an error: {e}")
        return False