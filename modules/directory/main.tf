###############################################################################
# MODULE: DIRECTORY SERVICE (AWS Managed Microsoft AD)
# Provides user authentication for WorkSpaces
# Note: Simple AD is NOT available in ap-south-1 (Mumbai)
###############################################################################

resource "aws_directory_service_directory" "managed_ad" {
  name     = var.directory_name
  password = var.admin_password
  edition  = var.directory_size   # "Standard" or "Enterprise"
  type     = "MicrosoftAD"

  vpc_settings {
    vpc_id     = var.vpc_id
    subnet_ids = var.subnet_ids
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-managed-ad"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────────────────────
variable "project_name" { type = string }
variable "environment" { type = string }
variable "directory_name" { type = string }
variable "directory_size" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────
output "directory_id" {
  description = "Directory ID"
  value       = aws_directory_service_directory.managed_ad.id
}

output "dns_ip_addresses" {
  description = "DNS IP addresses of the directory"
  value       = aws_directory_service_directory.managed_ad.dns_ip_addresses
}

output "directory_name" {
  description = "Directory FQDN"
  value       = aws_directory_service_directory.managed_ad.name
}
