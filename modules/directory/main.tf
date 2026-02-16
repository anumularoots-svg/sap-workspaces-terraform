###############################################################################
# MODULE: DIRECTORY SERVICE (AWS Simple AD)
# Provides user authentication for WorkSpaces
###############################################################################

resource "aws_directory_service_directory" "simple_ad" {
  name     = var.directory_name
  password = var.admin_password
  size     = var.directory_size
  type     = "SimpleAD"

  vpc_settings {
    vpc_id     = var.vpc_id
    subnet_ids = var.subnet_ids
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-simple-ad"
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
  value       = aws_directory_service_directory.simple_ad.id
}

output "dns_ip_addresses" {
  description = "DNS IP addresses of the directory"
  value       = aws_directory_service_directory.simple_ad.dns_ip_addresses
}

output "directory_name" {
  description = "Directory FQDN"
  value       = aws_directory_service_directory.simple_ad.name
}
