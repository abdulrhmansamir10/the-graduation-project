#!/bin/bash
# ============================================================================
# EC2 Instance Bootstrap Script (User Data)
# ============================================================================
#
# WHAT: Runs once when EC2 instance first launches
#
# WHY: Automated setup without manual intervention
# - Self-healing: New instances configure themselves
# - Consistency: Every instance configured identically
# - Speed: Full deployment in 3-5 minutes
#
# EXECUTION CONTEXT:
# - Runs as root user
# - Executes before SSH access available
# - Logs to /var/log/user-data.log
# - Terraform injects variables via templatefile()
#
# WHAT HAPPENS IF THIS FAILS:
# - Instance launches but application doesn't start
# - ASG health checks fail after grace period (5 min)
# - ASG terminates instance and tries again
# - Logs available in /var/log/user-data.log for debugging
# ============================================================================

set -e  # Exit on any error (fail fast)

# ----------------------------------------------------------------------------
# Setup Logging
# ----------------------------------------------------------------------------
# WHY: Debugging failed bootstraps requires logs
# LOCATION: /var/log/user-data.log (accessible via SSH if needed)
# ----------------------------------------------------------------------------
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "============================================"
echo "DevOps Project Bootstrap Script"
echo "Started: $(date)"
echo "Instance: $(uname -n)"
echo "============================================"

# ----------------------------------------------------------------------------
# Step 1: Associate Elastic IP
# ----------------------------------------------------------------------------
# WHAT: Claim the Elastic IP for this instance
#
# WHY FIRST: Ensures consistent IP address immediately
# - Users can connect via same IP even during replacement
# - DNS doesn't need updating
# - SSL certificates remain valid
#
# HOW IT WORKS:
# 1. Query metadata service for instance ID (169.254.169.254)
# 2. Use AWS CLI to associate pre-created EIP
# 3. EIP instantly points to this new instance
#
# SECURITY: IAM role grants permission (see iam.tf)
#
# FAILURE HANDLING:
# - If fails: Health checks fail, ASG retries with new instance
# - Rare failure: EIP already associated (race condition)
#   Solution: AWS API handles this gracefully
# ----------------------------------------------------------------------------
echo "[Step 1/10] Installing AWS CLI and associating Elastic IP..."

# Install AWS CLI v2 (awscli package not available on Ubuntu 24.04)
apt-get update -qq
apt-get install -y unzip curl > /dev/null 2>&1
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install > /dev/null 2>&1
rm -rf /tmp/awscliv2.zip /tmp/aws
echo "AWS CLI installed: $(aws --version)"

# IMDSv2: Get token first (required by launch template security settings)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
echo "Instance ID: $INSTANCE_ID"

aws ec2 associate-address \
  --instance-id $INSTANCE_ID \
  --allocation-id ${eip_allocation_id} \
  --region eu-north-1 \
  --allow-reassociation  # Handles rare race conditions

echo "✅ Elastic IP associated successfully"

# ----------------------------------------------------------------------------
# Step 2: System Updates
# ----------------------------------------------------------------------------
# WHY: Security patches and latest packages
# TRADEOFF: Adds ~60 seconds to boot time
# ALTERNATIVE: Pre-baked AMI (more complex, harder to maintain)
# ----------------------------------------------------------------------------
echo "[Step 2/10] Updating system packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

echo "✅ System updated"

# ----------------------------------------------------------------------------
# Step 3: Install Docker
# ----------------------------------------------------------------------------
# WHAT: Container runtime for running our application
#
# WHY DOCKER:
# - Consistent environment (dev = prod)
# - Isolation (frontend, backend, redis separate)
# - Easy updates (pull new images)
# - Industry standard (used by 70% of companies)
#
# METHOD: Official Docker installation script
# - Maintained by Docker Inc.
# - Handles all dependencies
# - Works across Ubuntu versions
# ----------------------------------------------------------------------------
echo "[Step 3/10] Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh > /dev/null 2>&1

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group (passwordless docker commands)
usermod -aG docker ubuntu

echo "✅ Docker installed: $(docker --version)"

# ----------------------------------------------------------------------------
# Step 4: Install Docker Compose
# ----------------------------------------------------------------------------
# WHAT: Orchestration tool for multi-container applications
#
# WHY NEEDED:
# - We run 3 containers (frontend, backend, redis)
# - Compose manages networking, dependencies, startup order
# - Single command to start/stop entire application
#
# VERSION: 2.20.0 (latest stable as of Dec 2024)
# LOCATION: /usr/local/bin/docker-compose (added to PATH)
# ----------------------------------------------------------------------------
echo "[Step 4/10] Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="2.20.0"
curl -L "https://github.com/docker/compose/releases/download/v$${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "✅ Docker Compose installed: $(docker-compose --version)"

# ----------------------------------------------------------------------------
# Step 5: Create Application Directory
# ----------------------------------------------------------------------------
# WHY: Organized file structure
# CONTENTS:
# - docker-compose.yml (orchestration)
# - .env (secrets - never committed to git!)
# - nginx/ssl (SSL certificates)
# ----------------------------------------------------------------------------
echo "[Step 5/10] Setting up application directory..."
mkdir -p /home/ubuntu/app
mkdir -p /home/ubuntu/app/nginx/ssl
cd /home/ubuntu/app

# Set ownership (docker group needs access)
chown -R ubuntu:ubuntu /home/ubuntu/app

echo "✅ Application directory created"

# ----------------------------------------------------------------------------
# Step 6: Create docker-compose.yml
# ----------------------------------------------------------------------------
# WHAT: Defines our multi-container application
#
# IMPORTANT: This uses RDS for PostgreSQL (not containerized)
# - No PostgreSQL container (removed)
# - Backend connects to RDS endpoint
# - Only Redis container for caching
# ----------------------------------------------------------------------------
echo "[Step 6/10] Creating docker-compose.yml..."
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  # Redis Cache (PostgreSQL moved to RDS!)
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server --requirepass $${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - app-network

  # Backend API (connects to RDS)
  backend:
    image: ghcr.io/${github_username}/${github_repo}:latest
    container_name: app-backend
    restart: unless-stopped
    depends_on:
      redis:
        condition: service_healthy
    environment:
      # RDS Database connection
      POSTGRES_HOST: ${db_host}
      POSTGRES_PORT: 5432
      POSTGRES_DB: ${db_name}
      POSTGRES_USER: ${db_user}
      POSTGRES_PASSWORD: ${db_password}
      # Redis
      REDIS_URL: redis://:$${REDIS_PASSWORD}@redis:6379/0
      # App
      SECRET_KEY: ${app_secret_key}
      FLASK_ENV: production
    expose:
      - "5000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "5"
    networks:
      - app-network

  # Frontend (Nginx)
  frontend:
    image: ghcr.io/${github_username}/${github_repo}-frontend:latest
    container_name: app-frontend
    restart: unless-stopped
    depends_on:
      - backend
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/ssl:/etc/nginx/ssl:ro
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - app-network

volumes:
  redis_data:

networks:
  app-network:
    driver: bridge
EOF

echo "✅ docker-compose.yml created"

# ----------------------------------------------------------------------------
# Step 7: Create .env File
# ----------------------------------------------------------------------------
# WHAT: Environment variables (secrets, config)
#
# WHY .env FILE:
# - Separates secrets from code
# - Easy to update without rebuilding images
# - docker-compose automatically reads it
#
# SECURITY:
# - Never committed to git (.gitignore)
# - Only readable by root and ubuntu user
# - Values injected by Terraform from variables
# ----------------------------------------------------------------------------
echo "[Step 7/10] Creating .env file..."
cat > .env <<'ENV_EOF'
# Container Registry
GITHUB_USERNAME=${github_username}
GITHUB_REPO=${github_repo}

# RDS Database
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}

# Redis
REDIS_PASSWORD=${redis_password}

# Application
APP_SECRET_KEY=${app_secret_key}
ENV_EOF

# Secure the .env file (sensitive data!)
chmod 600 .env
chown ubuntu:ubuntu .env

echo "✅ .env file created (secured)"

# ----------------------------------------------------------------------------
# Step 8: Pull and Start Containers
# ----------------------------------------------------------------------------
# WHAT: Download images from GitHub Container Registry and start app
#
# WHY SEPARATE STEPS:
# 1. Pull first = better error handling
# 2. If pull fails, we know before starting
#
# IMAGES:
# - Backend: ghcr.io/<username>/the-graduation-project:latest
# - Frontend: ghcr.io/<username>/the-graduation-project-frontend:latest
# - Redis: redis:7-alpine (Docker Hub - official)
#
# NOTE: For public images, no login needed
# For private images: Use GitHub token (not implemented here)
# ----------------------------------------------------------------------------
echo "[Step 8/10] Pulling Docker images..."
docker-compose pull

echo "[Step 9/10] Starting containers..."
docker-compose up -d

# Wait for services to initialize
echo "Waiting 30 seconds for services to start..."
sleep 30

# ----------------------------------------------------------------------------
# Step 9: Health Check
# ----------------------------------------------------------------------------
# WHY: Verify application started correctly
# FAILURE: Logged for debugging, ASG will retry
# ----------------------------------------------------------------------------
echo "[Step 10/10] Running health check..."
if curl -f http://localhost/health 2>/dev/null; then
  echo "✅ Application started successfully!"
  docker-compose ps
else
  echo "⚠️  Health check failed - check logs"
  docker-compose logs
fi

# ----------------------------------------------------------------------------
# Final Steps: Security Hardening
# ----------------------------------------------------------------------------
# Install Certbot for SSL (manual setup required)
echo "Installing Certbot..."
apt-get install -y certbot python3-certbot-nginx > /dev/null 2>&1

# Configure firewall
echo "Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "============================================"
echo "Bootstrap Complete: $(date)"
echo "============================================"

exit 0
