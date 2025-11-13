FROM python:3.11-alpine

# Create non-root user
#RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

# Install Python deps first (better caching)
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt && \
    rm -rf /var/cache/apk/* /tmp/*

    # Copy app - this will now copy app.py and utils.py into /app/
COPY . . 

# Drop privileges
#USER app
# Start the Flask app with gunicorn

CMD ["gunicorn", "-b", "0.0.0.0:5000", "-k", "gthread", "--threads", "4", "--timeout", "30", "app:app"]