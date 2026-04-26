# Stage 1: Build
FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .

# Install dependencies into a virtual environment to copy over
RUN python -m venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Production
FROM python:3.12-slim

WORKDIR /app

# Copy virtual env from builder
COPY --from=builder /opt/venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

COPY app.py .

# Create a non-root user and change ownership
RUN useradd -m -u 1001 appuser && \
    chown -R appuser:appuser /app

USER 1001

EXPOSE 8080

# Use Gunicorn as the production WSGI server
CMD ["gunicorn", "--workers=2", "--threads=4", "--bind=0.0.0.0:8080", "app:app"]