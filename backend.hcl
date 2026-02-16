###############################################################################
# Terraform Backend Configuration
# Account: 657246200133
# 
# Usage: terraform init -backend-config="backend.hcl"
###############################################################################

bucket         = "lanciere-terraform-state-657246200133"
key            = "sap-workspaces/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "terraform-lock"
encrypt        = true
