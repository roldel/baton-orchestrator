FROM python:3.11-alpine

# Create non-root user with a fixed, known UID/GID (not an auto-assigned -S
# system account): docker-compose.yml bind-mounts /srv/webhooks/queue into
# this container read-write, and bind mounts match host/container
# permissions by raw UID number, not by username — setup.sh chowns that
# host directory to this same 1000:1000 so the app can still write its
# redeploy task queue after dropping root.
RUN addgroup -g 1000 app && adduser -D -u 1000 -G app app

WORKDIR /app

# Install Python deps first (better caching)
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt && \
    rm -rf /var/cache/apk/* /tmp/*

    # Copy app - this will now copy app.py and utils.py into /app/
COPY . .

# Drop privileges. NOTE: /srv/projects (bind-mounted read-only as
# /app/projects) must stay readable by UID 1000 — the common default
# (world-readable files) already satisfies this; only a project .env
# deliberately chmod'd to be unreadable by "other" would need adjusting.
USER app
# Start the Flask app with gunicorn

CMD ["gunicorn", "-b", "0.0.0.0:5000", "-k", "gthread", "--threads", "4", "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", "app:app"]