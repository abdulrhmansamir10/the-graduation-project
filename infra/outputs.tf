# ============================================================================
# TERRAFORM OUTPUTS
# ============================================================================
# These values are displayed after terraform apply and can be queried with:
# terraform output <output_name>
# ============================================================================

# Application Access
output "application_url" {
  description = "URL to access the application (use this IP in your browser)"
  value       = "http://${aws_eip.devops_eip.public_ip}"
}

output "elastic_ip" {
  description = "Elastic IP address (consistent across instance replacements)"
  value       = aws_eip.devops_eip.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i <your-key.pem> ubuntu@${aws_eip.devops_eip.public_ip}"
}

# Database Connection
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (hostname:port)"
  value       = aws_db_instance.main.endpoint
}

output "rds_hostname" {
  description = "RDS hostname (for application configuration)"
  value       = aws_db_instance.main.address
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

# Network Information
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.devops_vpc.id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value = {
    subnet_1 = aws_subnet.devops_subnet_1.id
    subnet_2 = aws_subnet.devops_subnet_2.id
  }
}

# Auto Scaling Group
output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.app_asg.name
}

# State Backend Info
output "state_bucket" {
  description = "S3 bucket storing Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

# Security Group IDs (useful for debugging)
output "security_group_ids" {
  description = "Security group IDs"
  value = {
    app_sg = aws_security_group.devops_sg.id
    rds_sg = aws_security_group.rds_sg.id
  }
}
