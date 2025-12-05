# Ansible - Configuration Management

## 📁 Simple Structure

```
ansible/
├── ansible.cfg                     # Ansible settings
├── inventory/
│   ├── aws_ec2.yml                 # Dynamic inventory (auto-discovers servers)
│   └── static.ini                  # Backup inventory
├── playbooks/
│   ├── provision.yml               # Full server setup
│   └── deploy.yml                  # Quick app updates
├── templates/
│   ├── docker-compose.yml.j2       # Docker Compose template
│   └── env.j2                      # Environment variables template
├── vars.yml                        # All configuration variables
└── README.md                       # This file
```

## 🎯 Terraform vs Ansible - What's the Difference?

**Terraform** (Phase 1 - Infrastructure):
- **Creates** AWS resources: VPC, EC2, RDS, Security Groups
- Answers: "What servers exist?"
- Example: "Create a t3.micro EC2 instance"

**Ansible** (Phase 4 - Configuration):
- **Configures** those servers: Installs Docker, deploys apps
- Answers: "What's running on those servers?"
- Example: "Install Docker on the EC2 instance"

**Currently you have**: `user_data.sh` (bash script on EC2 startup)  
**Ansible replaces**: The bash script with professional automation

## 🚀 Quick Start

### 1. Install Ansible

```bash
# macOS
brew install ansible

# Ubuntu/Debian
sudo apt install ansible

# Python
pip3 install ansible
```

### 2. Install Collections

```bash
ansible-galaxy collection install community.docker
ansible-galaxy collection install amazon.aws
```

### 3. Configure AWS Credentials

```bash
aws configure
```

### 4. Test Dynamic Inventory

```bash
# List discovered servers
ansible-inventory -i inventory/aws_ec2.yml --graph

# Test connection
ansible all -i inventory/aws_ec2.yml -m ping
```

### 5. Run Provisioning

```bash
# Dry run (see what would change)
ansible-playbook playbooks/provision.yml --check

# Full run with secrets
ansible-playbook playbooks/provision.yml \
  -e "db_password=YOUR_DB_PASSWORD" \
  -e "redis_password=YOUR_REDIS_PASSWORD" \
  -e "app_secret_key=YOUR_SECRET_KEY"
```

## 📖 See Full Walkthrough

Check the **Phase 4 Walkthrough** document for complete explanation!
