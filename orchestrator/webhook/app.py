# orchestrator/webhook/app.py

import os
from flask import Flask, request, abort

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 5 * 1024 * 1024

# -----------------------------------------------------------------------------
# Global config (overridable via environment variables)
# -----------------------------------------------------------------------------
# Inside the container, /app/projects is a bind mount of /srv/projects on the host.
WEBHOOK_PROJECTS_DIR = os.environ.get(
    "WEBHOOK_PROJECTS_DIR",
    os.path.join(os.path.dirname(__file__), "projects"), # This resolves to /app/projects
)

SIGNAL_TO_HOST_DIR = os.environ.get(
    "SIGNAL_TO_HOST_DIR",
    "/signal-to-host"
)

# -----------------------------------------------------------------------------
# Routes
# -----------------------------------------------------------------------------
@app.get("/health")
def health():
    return "OK", 200



# NEW ENDPOINT FOR TESTING
@app.post("/write")
def write_test_file():
    try:
        test_filename = os.path.join(SIGNAL_TO_HOST_DIR, "test_file_simple.baton")
        with open(test_filename, "w") as f:
            f.write("This is a test file created by Flask.\n")
        return f"Test file created: {test_filename}", 200
    except Exception as e:
        abort(500, description=f"Failed to create test file: {str(e)}")

@app.post("/write")
def write_test_file():
    try:
        # Renamed to distinguish from atomic test
        test_filename = os.path.join(SIGNAL_TO_HOST_DIR, "test_file_atomic.baton")
        with open(test_filename, "w") as f:
            f.write("This is a test file created by Flask simply.\n")
        return f"Simple test file created: {test_filename}", 200
    except Exception as e:
        abort(500, description=f"Failed to create simple test file: {str(e)}")

# NEW ENDPOINT FOR ATOMIC TESTING
@app.post("/write-atomic")
def write_atomic_test_file():
    try:
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        test_filename = f"task_{timestamp}_atomic_test.baton"

        with tempfile.NamedTemporaryFile(mode="w", dir=SIGNAL_TO_HOST_DIR, delete=False) as temp_file:
            temp_path = temp_file.name
            temp_file.write("This is an atomically created test file from Flask.\n")

        final_path = os.path.join(SIGNAL_TO_HOST_DIR, test_filename)
        os.rename(temp_path, final_path)
        return f"Atomic test file created: {final_path}", 200
    except Exception as e:
        abort(500, description=f"Failed to create atomic test file: {str(e)}")



@app.post("/webhook")
def webhook():
    from utils import process_webhook_request
    # Pass the updated WEBHOOK_PROJECTS_DIR explicitly to process_webhook_request
    return process_webhook_request(request, WEBHOOK_PROJECTS_DIR, SIGNAL_TO_HOST_DIR)

# -----------------------------------------------------------------------------
# Local dev entrypoint
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    # This will ensure /srv/projects exists on the host if app.py is run locally outside docker
    # In Docker, it mostly just confirms the mount point exists.
    os.makedirs(WEBHOOK_PROJECTS_DIR, exist_ok=True)
    os.makedirs(SIGNAL_TO_HOST_DIR, exist_ok=True)
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")))