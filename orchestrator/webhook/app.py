from flask import Flask, request, abort
import os
import hmac
import hashlib
import json
from datetime import datetime

# Import utility functions
from . import utils

app = Flask(__name__)

# Base directory for webhook projects, relative to the webhook app's root
WEBHOOK_PROJECTS_DIR = os.path.join(os.path.dirname(__file__), 'projects')
# Directory where task files will be written for the host to pick up
SIGNAL_TO_HOST_DIR = '/signal-to-host'


@app.route('/health', methods=['GET'])
def health_check():
    """Simple health check endpoint."""
    return "OK", 200

@app.route('/webhook/<project_id>', methods=['POST'])
def handle_project_webhook(project_id):
    """
    Handles incoming webhook payloads for a specific project.
    """
    if request.method != 'POST':
        abort(400) # Bad Request for non-POST methods

    print(f"Received webhook for project_id: {project_id}")
    payload = request.get_data()
    signature_header = request.headers.get('X-Hub-Signature-256')

    # 1. Find matching project
    project_name, project_env = utils.find_matching_project(project_id, WEBHOOK_PROJECTS_DIR)
    
    if not project_name:
        print(f"No matching project found for project_id: {project_id}")
        abort(404) # Not Found if no project matches the ID

    print(f"Match found for project: {project_name}")

    # 2. Verify signature if required
    secret = project_env.get('PAYLOAD_SIGNATURE')
    if secret:
        if not utils.verify_signature(payload, signature_header, secret):
            print("ERROR: Signature verification failed.")
            abort(403) # Forbidden
        print("Signature verified successfully.")
    else:
        print("No PAYLOAD_SIGNATURE defined for project, skipping signature verification.")

    # 3. Process payload and determine task parameters
    return process_and_queue_redeploy(project_name, project_env, payload)

def process_and_queue_redeploy(project_name, project_env, payload):
    """
    Processes the webhook payload and queues a redeploy task by writing a file.
    """
    print(f"Processing webhook for project: {project_name}")

    # Determine REPO_LOCATION
    # Default to a path within the webhook container's 'projects' directory if CUSTOM_REPO_LOCATION is not set.
    # The actual host path where git pull runs will be determined by auto-redeploy.sh
    repo_location = project_env.get('CUSTOM_REPO_LOCATION', os.path.join('/projects-host-mapped', project_name))
    
    # Determine DOCKER_COMPOSE_RESTART_REQUIRED
    docker_restart_required = project_env.get('DOCKER_COMPOSE_RESTART_REQUIRED', 'NO')
    commit_docker_restart_trigger = project_env.get('COMMIT_DOCKER_COMPOSE_RESTART_TRIGGER')

    if docker_restart_required == 'NO' and commit_docker_restart_trigger:
        try:
            webhook_json = json.loads(payload)
            latest_commit_message = webhook_json.get('head_commit', {}).get('message', '')
            if commit_docker_restart_trigger in latest_commit_message:
                docker_restart_required = 'YES'
                print(f"Commit message triggered Docker restart: '{commit_docker_trigger}' found.")
        except json.JSONDecodeError:
            print("WARNING: Could not decode webhook payload as JSON for commit message check.")
        except KeyError as e:
            print(f"WARNING: Missing expected key in webhook payload for commit message check: {e}")


    ci_pipeline_location = project_env.get('CI_PEPLINE_LOCATION', '')
    custom_redeploy_script_location = project_env.get('CUSTOM_REDEPLOY_SCRIPT_LOCATION', '')

    # 4. Write task file
    try:
        task_file_path = utils.write_task_file(
            SIGNAL_TO_HOST_DIR,
            project_name,
            repo_location,
            docker_restart_required,
            ci_pipeline_location,
            custom_redeploy_script_location
        )
        print(f"Task file created: {task_file_path}")
        return 'Webhook processed and task file created!', 200
    except Exception as e:
        print(f"ERROR: Failed to write task file: {e}")
        abort(500) # Internal Server Error

if __name__ == '__main__':

    # Ensure critical directories exist if running locally for quick tests
    os.makedirs(WEBHOOK_PROJECTS_DIR, exist_ok=True)
    os.makedirs(SIGNAL_TO_HOST_DIR, exist_ok=True)
    
    app.run(host='0.0.0.0', port=5000)