###############################################################################
# POC Configuration - 2 WorkSpaces (Free Tier eligible)
# Usage: terraform apply -var-file="environments/poc.tfvars"
###############################################################################

aws_region   = "ap-south-1"
project_name = "sap-training-lab"
environment  = "poc"

# Network
vpc_cidr             = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]
enable_nat_gateway   = true

# Directory
directory_name = "sap-lab.local"
directory_size = "Small"

# WorkSpaces - POC (2 for Free Tier testing)
student_count             = 2
student_prefix            = "student"
student_email_domain      = "lancieretech.com"
workspace_bundle_id       = "wsb-clj85qzj1"  # Standard Linux
auto_stop_timeout_minutes = 10
root_volume_size          = 80
user_volume_size          = 50
volume_encryption_enabled = false
enable_self_service       = true

# Scheduler
eod_stop_cron        = "cron(30 14 ? * MON-FRI *)"  # 8 PM IST
morning_start_cron   = "cron(0 4 ? * MON-FRI *)"    # 9:30 AM IST
enable_morning_start = false

# Monitoring
alarm_email = ""  # Set your email for alerts

# Tags
additional_tags = {
  Phase   = "POC"
  Trainer = "SAP-Basis"
}
