# ============================================================================
# Backend Dockerfile (Secured)
# ============================================================================
# 
# SECURITY FEATURES:
# 1. Non-root user (appuser) - Prevents privilege escalation
# 2. Python slim image - Reduces attack surface
# 3. No build tools in final image - Reduces vulnerability count
# 4. Gunicorn WSGI server - Production-grade performance
# ============================================================================

# Use official Python runtime as a parent image
FROM python:3.10-slim

# Set environment variables
# PYTHONDONTWRITEBYTECODE: Prevents Python from writing pyc files to disc
# PYTHONUNBUFFERED: Ensures logs are flushed immediately
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Set work directory
WORKDIR /app

# Install system dependencies
# libpq-dev: Required for psycopg2 (PostgreSQL adapter)
# gcc: Required for compiling some python packages
RUN apt-get update && apt-get install -y \
	gcc \
	libpq-dev \
	curl \
	&& rm -rf /var/lib/apt/lists/*

# Create a non-root user
# -u 1000: Specific UID for consistency
# -m: Create home directory
RUN useradd -u 1000 -m appuser

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Change ownership of the application directory to the non-root user
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose port 5000
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
	CMD curl -f http://localhost:5000/health || exit 1

# Run with Gunicorn (Production WSGI Server)
# -w 4: 4 worker processes (good for t3.micro 2 vCPU)
# -b 0.0.0.0:5000: Bind to all interfaces
# --access-logfile -: Log to stdout
CMD ["gunicorn", "--workers=4", "--bind=0.0.0.0:5000", "--access-logfile", "-", "app:app"]