###############################################################################
# SAP Training Lab - AWS WorkSpaces Infrastructure
# Lanciere Technologies - DevOps Automation
# 
# Description: Complete Terraform automation for provisioning 40 AWS WorkSpaces
#              for SAP Basis training with auto-stop (10 min idle) and 
#              self-service start capabilities.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Remote state - Account: 657246200133
  # Initialize with: terraform init -backend-config="backend.hcl"
  backend "s3" {
    # Values provided via backend.hcl file
    # bucket         = "lanciere-terraform-state-657246200133"
    # key            = "sap-workspaces/terraform.tfstate"
    # region         = "ap-south-1"
    # dynamodb_table = "terraform-lock"
    # encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SAP-Training-Lab"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Lanciere-Technologies"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE: VPC & NETWORKING
# ─────────────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  
  enable_nat_gateway = var.enable_nat_gateway
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE: DIRECTORY SERVICE (Simple AD)
# ─────────────────────────────────────────────────────────────────────────────
module "directory" {
  source = "./modules/directory"

  project_name    = var.project_name
  environment     = var.environment
  directory_name  = var.directory_name
  directory_size  = var.directory_size
  admin_password  = var.ad_admin_password
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE: AWS WORKSPACES
# ─────────────────────────────────────────────────────────────────────────────
module "workspaces" {
  source = "./modules/workspaces"

  project_name     = var.project_name
  environment      = var.environment
  directory_id     = module.directory.directory_id
  subnet_ids       = module.vpc.private_subnet_ids
  
  # Student configuration
  student_count        = var.student_count
  student_prefix       = var.student_prefix
  student_email_domain = var.student_email_domain
  
  # WorkSpace configuration
  bundle_id                   = var.workspace_bundle_id
  running_mode                = "AUTO_STOP"
  running_mode_auto_stop_timeout = var.auto_stop_timeout_minutes
  
  # Volume sizes
  root_volume_size = var.root_volume_size
  user_volume_size = var.user_volume_size
  
  # Volume encryption
  volume_encryption_enabled = var.volume_encryption_enabled
  
  # Self-service permissions
  enable_self_service = var.enable_self_service
  
  # Security group
  vpc_id = module.vpc.vpc_id
  
  # Tags
  additional_tags = var.additional_tags

  depends_on = [module.directory]
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE: LAMBDA SCHEDULER (End-of-Day Bulk Stop + Morning Health Check)
# ─────────────────────────────────────────────────────────────────────────────
module "lambda_scheduler" {
  source = "./modules/lambda-scheduler"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  
  # Schedule (IST = UTC+5:30)
  eod_stop_schedule    = var.eod_stop_cron       # e.g., "cron(30 14 ? * MON-FRI *)" = 8 PM IST
  morning_start_schedule = var.morning_start_cron # Optional: pre-start before class
  
  enable_morning_start = var.enable_morning_start
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE: MONITORING (CloudWatch Dashboard + Alarms)
# ─────────────────────────────────────────────────────────────────────────────
module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  
  directory_id  = module.directory.directory_id
  student_count = var.student_count
  
  alarm_email = var.alarm_email
}
