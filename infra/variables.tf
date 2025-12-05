# ============================================================================
# Terraform Variables
# ============================================================================
# WHAT: Input parameters for Terraform configuration
#
# WHY VARIABLES:
# - Avoid hardcoding sensitive data
# - Reuse configuration across environments
# - Allow customization without changing code
# - Required for Terraform best practices
#
# HOW TO USE:
# 1. Create terraform.tfvars file (gitignored!)
# 2. Set values there
# 3. Never commit terraform.tfvars to git!
#
# SECURITY: Variables marked 'sensitive = true' won't appear in logs
# ============================================================================

# ----------------------------------------------------------------------------
# Network Security
# ----------------------------------------------------------------------------
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into instances (YOUR IP/32)"
  type        = string
  sensitive   = true

  # EXAMPLE: "203.0.113.42/32"
  # FIND YOUR IP: curl ifconfig.me
  # ADD /32 at the end to restrict to exactly that IP
}

# ----------------------------------------------------------------------------
# Database Configuration
# ----------------------------------------------------------------------------
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "appdb"

  validation {
    condition     = length(var.db_name) > 0 && length(var.db_name) <= 63
    error_message = "Database name must be 1-63 characters"
  }
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_username) > 0
    error_message = "Database username cannot be empty"
  }
}

variable "db_password" {
  description = "PostgreSQL master password (min 20 characters recommended)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Password must be at least 8 characters (20+ recommended)"
  }
}

# ----------------------------------------------------------------------------
# Container Registry Configuration
# ----------------------------------------------------------------------------
variable "github_username" {
  description = "GitHub username for GHCR (GitHub Container Registry)"
  type        = string

  # EXAMPLE: "john-doe"
  # Your GitHub username in lowercase
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "the-graduation-project"

  # Must match your GitHub repository name exactly
}

# ----------------------------------------------------------------------------
# Application Secrets
# ----------------------------------------------------------------------------
variable "redis_password" {
  description = "Redis authentication password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redis_password) >= 8
    error_message = "Redis password must be at least 8 characters (20+ recommended)"
  }
}

variable "app_secret_key" {
  description = "Flask application secret key (for session security)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.app_secret_key) >= 32
    error_message = "Secret key must be at least 32 characters (48+ recommended)"
  }
}

# ============================================================================
# HOW TO CREATE terraform.tfvars:
# ============================================================================
# Create file: infra/terraform.tfvars
#
# Content:
# ```hcl
# # Get your IP
# allowed_ssh_cidr = "203.0.113.42/32"  # Replace with your IP from 'curl ifconfig.me'
#
# # Database credentials (use strong passwords!)
# db_username = "dbadmin"
# db_password = "GENERATED_PASSWORD_HERE"  # Use: openssl rand -base64 32
#
# # GitHub configuration
# github_username = "your-github-username"
# github_repo     = "the-graduation-project"
#
# # Application secrets (generate strong random strings)
# redis_password  = "GENERATED_PASSWORD_HERE"  # Use: openssl rand -base64 32
# app_secret_key  = "GENERATED_SECRET_HERE"    # Use: openssl rand -base64 48
# ```
#
# GENERATE SECURE PASSWORDS:
# ```bash
# openssl rand -base64 32  # For DB and Redis passwords
# openssl rand -base64 48  # For app secret key
# ```
#
# CRITICAL: Add to .gitignore:
# ```
# # .gitignore
# infra/terraform.tfvars
# infra/*.tfvars
# *.auto.tfvars
# ```
# ============================================================================

# ============================================================================
# PRESENTATION NOTES:
# ============================================================================
# Q: Why separate variables file?
# A: Separation of concerns
#    - Code (*.tf files): Infrastructure logic
#    - Config (variables.tf): Interface definition
#    - Secrets (terraform.tfvars): Actual values (gitignored)
#    This is industry standard Terraform practice
#
# Q: Why not use default values for secrets?
# A: Security anti-pattern
#    - Default passwords = weak passwords
#    - Forces user to think about security
#    - No accidental commits of secrets to git
#    - Same approach AWS uses for all services
#
# Q: Alternative to terraform.tfvars?
# A: Several options:
#    1. Environment variables: TF_VAR_db_password
#    2. AWS Secrets Manager (production best practice)
#    3. HashiCorp Vault (enterprise solution)
#    4. terraform.tfvars (our choice - simple, effective)
# ============================================================================
