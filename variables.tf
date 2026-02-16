###############################################################################
# VARIABLES - SAP Training Lab WorkSpaces
###############################################################################

# ─────────────────────────────────────────────────────────────────────────────
# GENERAL
# ─────────────────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "sap-training-lab"
}

variable "environment" {
  description = "Environment (poc/dev/prod)"
  type        = string
  default     = "poc"
  validation {
    condition     = contains(["poc", "dev", "prod"], var.environment)
    error_message = "Environment must be one of: poc, dev, prod."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# NETWORKING
# ─────────────────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (WorkSpaces)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (NAT Gateway)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for internet access from WorkSpaces"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────────────
# DIRECTORY SERVICE
# ─────────────────────────────────────────────────────────────────────────────
variable "directory_name" {
  description = "FQDN for the Simple AD directory"
  type        = string
  default     = "sap-lab.local"
}

variable "directory_size" {
  description = "Edition of AWS Managed Microsoft AD (Standard or Enterprise)"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Enterprise"], var.directory_size)
    error_message = "Directory size must be Standard or Enterprise (Managed Microsoft AD)."
  }
}

variable "ad_admin_password" {
  description = "Admin password for Simple AD (min 8 chars, uppercase, lowercase, number)"
  type        = string
  sensitive   = true
}

# ─────────────────────────────────────────────────────────────────────────────
# WORKSPACES CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
variable "student_count" {
  description = "Number of student WorkSpaces to create"
  type        = number
  default     = 40
  validation {
    condition     = var.student_count >= 1 && var.student_count <= 100
    error_message = "Student count must be between 1 and 100."
  }
}

variable "student_prefix" {
  description = "Username prefix for student accounts"
  type        = string
  default     = "student"
}

variable "student_email_domain" {
  description = "Email domain for student accounts"
  type        = string
  default     = "lancieretech.com"
}

variable "workspace_bundle_id" {
  description = "WorkSpaces bundle ID. Use 'wsb-clj85qzj1' for Standard Linux or run: aws workspaces describe-workspace-bundles --region ap-south-1"
  type        = string
  default     = "wsb-clj85qzj1" # Standard with Amazon Linux 2 (2 vCPU, 4 GiB RAM)
}

variable "auto_stop_timeout_minutes" {
  description = "Minutes of inactivity before WorkSpace auto-stops (minimum 10)"
  type        = number
  default     = 10
  validation {
    condition     = var.auto_stop_timeout_minutes >= 10
    error_message = "Auto-stop timeout must be at least 10 minutes."
  }
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 80
}

variable "user_volume_size" {
  description = "User volume size in GB"
  type        = number
  default     = 50
}

variable "volume_encryption_enabled" {
  description = "Enable volume encryption for WorkSpaces"
  type        = bool
  default     = false
}

variable "enable_self_service" {
  description = "Enable self-service permissions (restart, start from client)"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHEDULER
# ─────────────────────────────────────────────────────────────────────────────
variable "eod_stop_cron" {
  description = "Cron expression for end-of-day bulk stop (UTC). Default: 8 PM IST = 2:30 PM UTC"
  type        = string
  default     = "cron(30 14 ? * MON-FRI *)"
}

variable "morning_start_cron" {
  description = "Cron expression for morning pre-start (UTC). Default: 9:30 AM IST = 4:00 AM UTC"
  type        = string
  default     = "cron(0 4 ? * MON-FRI *)"
}

variable "enable_morning_start" {
  description = "Enable morning auto-start of all WorkSpaces before class"
  type        = bool
  default     = false
}

# ─────────────────────────────────────────────────────────────────────────────
# MONITORING
# ─────────────────────────────────────────────────────────────────────────────
variable "alarm_email" {
  description = "Email address for CloudWatch alarms"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# ADDITIONAL TAGS
# ─────────────────────────────────────────────────────────────────────────────
variable "additional_tags" {
  description = "Additional tags to apply to WorkSpaces"
  type        = map(string)
  default     = {}
}
