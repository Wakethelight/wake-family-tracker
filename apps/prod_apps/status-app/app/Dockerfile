FROM python:3.11-slim AS builder

WORKDIR /app

# Install deps in builder
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim

WORKDIR /app

# Copy deps from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy app code (includes app.py, models, static/, templates/, init_db.py, etc.)
COPY . .

# Expose port (App Service maps externally to 80)
EXPOSE 8000

# Run Gunicorn serving the Flask app defined in app.py
CMD gunicorn --bind=0.0.0.0:${PORT:-8000} --workers=2 --timeout=120 app:app
