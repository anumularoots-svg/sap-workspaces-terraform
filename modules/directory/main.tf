###############################################################################
# MODULE: DIRECTORY SERVICE
# Supports both SimpleAD (us-east-1, etc.) and MicrosoftAD (ap-south-1)
###############################################################################

resource "aws_directory_service_directory" "main" {
  name     = var.directory_name
  password = var.admin_password
  type     = var.directory_type

  # SimpleAD uses 'size', MicrosoftAD uses 'edition'
  size    = var.directory_type == "SimpleAD" ? var.directory_size : null
  edition = var.directory_type == "MicrosoftAD" ? var.directory_size : null

  vpc_settings {
    vpc_id     = var.vpc_id
    subnet_ids = var.subnet_ids
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-directory"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────────────────────
variable "project_name" { type = string }
variable "environment" { type = string }
variable "directory_name" { type = string }
variable "directory_type" {
  type    = string
  default = "SimpleAD"
}
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
  value = aws_directory_service_directory.main.id
}
output "dns_ip_addresses" {
  value = aws_directory_service_directory.main.dns_ip_addresses
}
output "directory_name" {
  value = aws_directory_service_directory.main.name
}
