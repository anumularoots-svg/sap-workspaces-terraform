###############################################################################
# OUTPUTS - SAP Training Lab WorkSpaces
###############################################################################

# ─────────────────────────────────────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (WorkSpaces)"
  value       = module.vpc.private_subnet_ids
}

# ─────────────────────────────────────────────────────────────────────────────
# DIRECTORY
# ─────────────────────────────────────────────────────────────────────────────
output "directory_id" {
  description = "Simple AD directory ID"
  value       = module.directory.directory_id
}

output "directory_dns_ips" {
  description = "DNS IP addresses of the directory"
  value       = module.directory.dns_ip_addresses
}

# ─────────────────────────────────────────────────────────────────────────────
# WORKSPACES
# ─────────────────────────────────────────────────────────────────────────────
output "workspace_ids" {
  description = "Map of student username to WorkSpace ID"
  value       = module.workspaces.workspace_ids
}

output "workspace_registration_code" {
  description = "Registration code for WorkSpaces client"
  value       = module.workspaces.registration_code
}

output "workspace_security_group_id" {
  description = "Security group ID for WorkSpaces"
  value       = module.workspaces.security_group_id
}

output "workspace_ip_addresses" {
  description = "Map of student username to WorkSpace IP address"
  value       = module.workspaces.workspace_ips
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHEDULER
# ─────────────────────────────────────────────────────────────────────────────
output "eod_stop_lambda_arn" {
  description = "ARN of the end-of-day stop Lambda function"
  value       = module.lambda_scheduler.eod_stop_lambda_arn
}

# ─────────────────────────────────────────────────────────────────────────────
# MONITORING
# ─────────────────────────────────────────────────────────────────────────────
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
}

# ─────────────────────────────────────────────────────────────────────────────
# STUDENT CONNECTION INFO
# ─────────────────────────────────────────────────────────────────────────────
output "student_connection_instructions" {
  description = "Instructions for students to connect"
  value       = <<-EOT
    ╔══════════════════════════════════════════════════════════════╗
    ║           SAP TRAINING LAB - CONNECTION GUIDE                ║
    ╠══════════════════════════════════════════════════════════════╣
    ║                                                              ║
    ║  1. Download AWS WorkSpaces Client:                          ║
    ║     https://clients.amazonworkspaces.com/                    ║
    ║                                                              ║
    ║  2. Registration Code: ${module.workspaces.registration_code}║
    ║                                                              ║
    ║  3. Login with your credentials:                             ║
    ║     Username: student01 (through student${format("%02d", var.student_count)})            ║
    ║     Password: (provided separately)                          ║
    ║                                                              ║
    ║  4. If WorkSpace is stopped, click 'Start' in the client     ║
    ║     (takes ~2-3 minutes to boot)                             ║
    ║                                                              ║
    ║  5. WorkSpace auto-stops after ${var.auto_stop_timeout_minutes} min of inactivity        ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
  EOT
}
