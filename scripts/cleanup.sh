#!/bin/bash
###############################################################################
# Script: cleanup.sh
# Description: Complete cleanup of SAP Training Lab infrastructure
# Account: 657246200133
#
# Usage: ./scripts/cleanup.sh [poc|prod]
###############################################################################

set -euo pipefail

ENV=${1:-"poc"}
AWS_ACCOUNT_ID="657246200133"
REGION="ap-south-1"
TF_STATE_BUCKET="lanciere-terraform-state-${AWS_ACCOUNT_ID}"
TF_LOCK_TABLE="terraform-lock"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ⚠️  SAP Training Lab - DESTROY ALL RESOURCES               ║"
echo "║  Account: ${AWS_ACCOUNT_ID}                                 ║"
echo "║  Environment: ${ENV}                                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Are you sure you want to destroy ALL resources? (type 'yes' to confirm): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: TERRAFORM DESTROY
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[Step 1] Running terraform destroy...${NC}"
read -sp "Enter AD admin password: " AD_PASSWORD
echo ""

terraform destroy \
  -var-file="environments/${ENV}.tfvars" \
  -var="ad_admin_password=${AD_PASSWORD}" \
  -auto-approve

echo -e "${GREEN}  ✅ Terraform resources destroyed.${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: CLEANUP BOOTSTRAP (Optional)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
read -p "Also destroy bootstrap resources (S3 state, DynamoDB, IAM)? (yes/no): " CLEANUP_BOOTSTRAP

if [ "$CLEANUP_BOOTSTRAP" = "yes" ]; then
  echo -e "${YELLOW}[Step 2a] Deleting S3 state bucket...${NC}"
  aws s3 rb "s3://${TF_STATE_BUCKET}" --force --region "${REGION}" 2>/dev/null || true
  echo -e "${GREEN}  ✅ S3 bucket deleted.${NC}"

  echo -e "${YELLOW}[Step 2b] Deleting DynamoDB lock table...${NC}"
  aws dynamodb delete-table --table-name "${TF_LOCK_TABLE}" --region "${REGION}" 2>/dev/null || true
  echo -e "${GREEN}  ✅ DynamoDB table deleted.${NC}"

  echo -e "${YELLOW}[Step 2c] Deleting IAM user and policy...${NC}"
  # Detach policy
  aws iam detach-user-policy \
    --user-name terraform-sap-workspaces \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SAPWorkSpacesTerraformPolicy" 2>/dev/null || true
  
  # Delete access keys
  for KEY in $(aws iam list-access-keys --user-name terraform-sap-workspaces --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null); do
    aws iam delete-access-key --user-name terraform-sap-workspaces --access-key-id "$KEY" 2>/dev/null || true
  done
  
  # Delete user
  aws iam delete-user --user-name terraform-sap-workspaces 2>/dev/null || true
  
  # Delete policy (all versions first)
  POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SAPWorkSpacesTerraformPolicy"
  for VER in $(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --query 'Versions[?!IsDefaultVersion].VersionId' --output text 2>/dev/null); do
    aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "$VER" 2>/dev/null || true
  done
  aws iam delete-policy --policy-arn "${POLICY_ARN}" 2>/dev/null || true
  
  echo -e "${GREEN}  ✅ IAM resources cleaned up.${NC}"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║               CLEANUP COMPLETE ✅                            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
