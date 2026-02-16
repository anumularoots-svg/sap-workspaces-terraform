###############################################################################
# MODULE: AWS WORKSPACES
# Creates WorkSpaces for all students with AutoStop, self-service, and 
# security configurations
###############################################################################

# ─────────────────────────────────────────────────────────────────────────────
# LOCAL VALUES
# ─────────────────────────────────────────────────────────────────────────────
locals {
  students = { for i in range(1, var.student_count + 1) :
    format("%s%02d", var.student_prefix, i) => {
      username   = format("%s%02d", var.student_prefix, i)
      first_name = "Student"
      last_name  = format("%02d", i)
      email      = format("%s%02d@%s", var.student_prefix, i, var.student_email_domain)
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# REGISTER DIRECTORY WITH WORKSPACES
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_workspaces_directory" "main" {
  directory_id = var.directory_id
  subnet_ids   = var.subnet_ids

  # Self-service permissions - allows students to start/restart their WorkSpace
  self_service_permissions {
    change_compute_type  = false
    increase_volume_size = false
    rebuild_workspace    = false
    restart_workspace    = var.enable_self_service
    switch_running_mode  = false
  }

  # Workspace access properties
  workspace_access_properties {
    device_type_android    = "ALLOW"
    device_type_chromeos   = "ALLOW"
    device_type_ios        = "ALLOW"
    device_type_linux      = "ALLOW"
    device_type_osx        = "ALLOW"
    device_type_web        = "ALLOW"
    device_type_windows    = "ALLOW"
    device_type_zeroclient = "ALLOW"
  }

  # Workspace creation properties
  workspace_creation_properties {
    enable_internet_access            = true
    enable_maintenance_mode           = true
    user_enabled_as_local_administrator = false  # Students should NOT be admin
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ws-directory"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUP FOR WORKSPACES
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "workspaces" {
  name_prefix = "${var.project_name}-${var.environment}-ws-"
  vpc_id      = var.vpc_id
  description = "Security group for SAP Training WorkSpaces"

  # Allow all outbound (for internet access, SAP server connectivity)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # SAP GUI ports (within VPC to SAP server)
  ingress {
    from_port   = 3200
    to_port     = 3299
    protocol    = "tcp"
    self        = true
    description = "SAP GUI dispatcher ports"
  }

  # SAP Message Server
  ingress {
    from_port   = 3600
    to_port     = 3699
    protocol    = "tcp"
    self        = true
    description = "SAP Message Server ports"
  }

  # SSH (for SAP Basis training)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    self        = true
    description = "SSH access within WorkSpaces"
  }

  # HANA Studio
  ingress {
    from_port   = 30013
    to_port     = 30015
    protocol    = "tcp"
    self        = true
    description = "SAP HANA SQL/HTTP ports"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ws-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# WORKSPACES - ONE PER STUDENT
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_workspaces_workspace" "student" {
  for_each = local.students

  directory_id = var.directory_id
  bundle_id    = var.bundle_id
  user_name    = each.value.username

  # AutoStop - Terraform enforces 60-min intervals minimum
  # Actual 10-min override applied via local-exec provisioner below
  workspace_properties {
    compute_type_name                         = "STANDARD"
    user_volume_size_gib                      = var.user_volume_size
    root_volume_size_gib                      = var.root_volume_size
    running_mode                              = var.running_mode
    running_mode_auto_stop_timeout_in_minutes = 60
  }

  # Volume encryption
  root_volume_encryption_enabled = var.volume_encryption_enabled
  user_volume_encryption_enabled = var.volume_encryption_enabled

  tags = merge(
    {
      Name     = "${var.project_name}-${var.environment}-${each.value.username}"
      Username = each.value.username
      Email    = each.value.email
    },
    var.additional_tags
  )

  # Wait for directory registration
  depends_on = [aws_workspaces_directory.main]

  # WorkSpaces take time to provision; prevent unnecessary recreation
  timeouts {
    create = "60m"
    update = "30m"
    delete = "30m"
  }

  lifecycle {
    ignore_changes = [
      workspace_properties[0].running_mode,
      workspace_properties[0].running_mode_auto_stop_timeout_in_minutes,
    ]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# OVERRIDE AUTO-STOP TO ACTUAL TIMEOUT (e.g., 10 min)
# Terraform provider only supports 60-min intervals, so we use AWS CLI
# ─────────────────────────────────────────────────────────────────────────────
resource "terraform_data" "set_autostop_timeout" {
  for_each = aws_workspaces_workspace.student

  triggers_replace = [
    each.value.id,
    var.running_mode_auto_stop_timeout
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Setting AutoStop timeout to ${var.running_mode_auto_stop_timeout} min for ${each.value.id} (${each.key})"
      aws workspaces modify-workspace-properties \
        --workspace-id ${each.value.id} \
        --workspace-properties "RunningMode=AUTO_STOP,RunningModeAutoStopTimeoutInMinutes=${var.running_mode_auto_stop_timeout}" \
        --region ${data.aws_region.current.name} 2>&1 || echo "Warning: Could not set timeout for ${each.value.id}"
    EOT
  }

  depends_on = [aws_workspaces_workspace.student]
}

data "aws_region" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────────────────────
variable "project_name" { type = string }
variable "environment" { type = string }
variable "directory_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "vpc_id" { type = string }

variable "student_count" { type = number }
variable "student_prefix" { type = string }
variable "student_email_domain" { type = string }

variable "bundle_id" { type = string }
variable "running_mode" { type = string }
variable "running_mode_auto_stop_timeout" { type = number }

variable "root_volume_size" { type = number }
variable "user_volume_size" { type = number }
variable "volume_encryption_enabled" { type = bool }
variable "enable_self_service" { type = bool }
variable "additional_tags" { type = map(string) }

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────
output "workspace_ids" {
  description = "Map of username to WorkSpace ID"
  value = {
    for k, v in aws_workspaces_workspace.student : k => v.id
  }
}

output "workspace_ips" {
  description = "Map of username to WorkSpace IP"
  value = {
    for k, v in aws_workspaces_workspace.student : k => v.ip_address
  }
}

output "registration_code" {
  description = "WorkSpaces registration code"
  value       = aws_workspaces_directory.main.registration_code
}

output "security_group_id" {
  description = "WorkSpaces security group ID"
  value       = aws_security_group.workspaces.id
}
