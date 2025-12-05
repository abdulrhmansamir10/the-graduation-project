#!/bin/bash
# ============================================================================
# EC2 Instance Bootstrap Script (MINIMAL VERSION)
# ============================================================================
#
# WHAT: Runs once when EC2 instance first launches
# WHY: Minimal setup for self-healing ASG + Ansible takes over configuration
#
# THIS SCRIPT ONLY:
# 1. Associates Elastic IP (required for consistent addressing)
# 2. Prepares base system for Ansible
#
# ANSIBLE HANDLES:
# - Docker installation
# - Application deployment
# - Configuration management
#
# ============================================================================

set -e  # Exit on any error

# Setup Logging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "============================================"
echo "DevOps Project Bootstrap (Minimal)"
echo "Started: $(date)"
echo "============================================"

# ----------------------------------------------------------------------------
# Step 1: Install AWS CLI and Associate Elastic IP
# ----------------------------------------------------------------------------
echo "[Step 1/3] Installing AWS CLI..."
apt-get update -qq
apt-get install -y unzip curl > /dev/null 2>&1
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install > /dev/null 2>&1
rm -rf /tmp/awscliv2.zip /tmp/aws
echo "AWS CLI installed: $(aws --version)"

echo "[Step 2/3] Associating Elastic IP..."
# IMDSv2: Get token first
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
echo "Instance ID: $INSTANCE_ID"

aws ec2 associate-address \
  --instance-id $INSTANCE_ID \
  --allocation-id ${eip_allocation_id} \
  --region eu-north-1 \
  --allow-reassociation

echo "✅ Elastic IP associated"

# ----------------------------------------------------------------------------
# Step 2: Install Python for Ansible
# ----------------------------------------------------------------------------
echo "[Step 3/3] Installing Python for Ansible..."
apt-get install -y python3 python3-pip > /dev/null 2>&1
echo "✅ Python installed: $(python3 --version)"

# ----------------------------------------------------------------------------
# Create app directory (Ansible expects this)
# ----------------------------------------------------------------------------
mkdir -p /home/ubuntu/app
chown -R ubuntu:ubuntu /home/ubuntu/app

echo "============================================"
echo "Bootstrap Complete: $(date)"
echo "Server ready for Ansible configuration"
echo "============================================"

exit 0
