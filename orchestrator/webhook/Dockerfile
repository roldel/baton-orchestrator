FROM python:3.11-alpine

# UID/GID 65532 is not a normal login account. The queue directory on the
# host is chowned to this numeric id (mode 0700) so only this process and
# root can write task files.
RUN addgroup -g 65532 baton && adduser -D -u 65532 -G baton baton

WORKDIR /app

# Install Python deps first (better caching)
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt && \
    rm -rf /var/cache/apk/* /tmp/*

    # Copy app - this will now copy app.py and utils.py into /app/
COPY . .

# Drop privileges. Project .env files must be readable by UID 65532.
USER baton
# Start the Flask app with gunicorn

CMD ["gunicorn", "-b", "0.0.0.0:5000", "-k", "gthread", "--threads", "4", "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", "app:app"]