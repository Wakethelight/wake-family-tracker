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

# Copy app code
COPY . .

# Expose port (App Service maps externally to 80)
EXPOSE 8000

# Run with Gunicorn
CMD ["gunicorn", "-b", "0.0.0.0:8000", "app:app"]