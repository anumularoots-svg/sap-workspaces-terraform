#!/bin/bash
###############################################################################
# Script: bootstrap.sh
# Description: One-time AWS account setup for SAP Training Lab
# Account: 657246200133
# Region: ap-south-1 (Mumbai)
#
# This script creates:
#  1. IAM User + Policy for Terraform execution
#  2. workspaces_DefaultRole (required by AWS WorkSpaces service)
#  3. S3 bucket + DynamoDB table for Terraform remote state
#  4. Discovers available WorkSpaces bundles
#
# Usage: chmod +x scripts/bootstrap.sh && ./scripts/bootstrap.sh
###############################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
AWS_ACCOUNT_ID="657246200133"
REGION="ap-south-1"
PROJECT="sap-training-lab"
TF_STATE_BUCKET="lanciere-terraform-state-${AWS_ACCOUNT_ID}"
TF_LOCK_TABLE="terraform-lock"
IAM_USER="terraform-sap-workspaces"
IAM_POLICY_NAME="SAPWorkSpacesTerraformPolicy"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     SAP Training Lab - AWS Account Bootstrap                ║"
echo "║     Account: ${AWS_ACCOUNT_ID}                              ║"
echo "║     Region:  ${REGION}                                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# VERIFY AWS CREDENTIALS
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[Step 0] Verifying AWS credentials...${NC}"

CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null) || {
  echo -e "${RED}ERROR: AWS CLI not configured. Run 'aws configure' first.${NC}"
  exit 1
}

ACTUAL_ACCOUNT=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
CALLER_ARN=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])")

if [ "$ACTUAL_ACCOUNT" != "$AWS_ACCOUNT_ID" ]; then
  echo -e "${RED}ERROR: Connected to account ${ACTUAL_ACCOUNT}, expected ${AWS_ACCOUNT_ID}${NC}"
  exit 1
fi

echo -e "${GREEN}  ✅ Connected as: ${CALLER_ARN}${NC}"
echo -e "${GREEN}  ✅ Account: ${ACTUAL_ACCOUNT}${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: CREATE workspaces_DefaultRole (Required by AWS WorkSpaces)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[Step 1] Creating workspaces_DefaultRole...${NC}"

ROLE_EXISTS=$(aws iam get-role --role-name workspaces_DefaultRole 2>/dev/null && echo "yes" || echo "no")

if [ "$ROLE_EXISTS" = "yes" ]; then
  echo -e "${GREEN}  ✅ workspaces_DefaultRole already exists. Skipping.${NC}"
else
  aws iam create-role \
    --role-name workspaces_DefaultRole \
    --assume-role-policy-document file://iam/workspaces-default-role-trust.json \
    --description "Default role for AWS WorkSpaces service" \
    --tags Key=Project,Value=${PROJECT} Key=ManagedBy,Value=bootstrap \
    --output text --query 'Role.Arn'

  # Attach required AWS managed policies
  aws iam attach-role-policy \
    --role-name workspaces_DefaultRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonWorkSpacesServiceAccess

  aws iam attach-role-policy \
    --role-name workspaces_DefaultRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonWorkSpacesSelfServiceAccess

  echo -e "${GREEN}  ✅ workspaces_DefaultRole created and policies attached.${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: CREATE TERRAFORM STATE S3 BUCKET
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[Step 2] Creating Terraform state S3 bucket...${NC}"

BUCKET_EXISTS=$(aws s3api head-bucket --bucket "${TF_STATE_BUCKET}" 2>/dev/null && echo "yes" || echo "no")

if [ "$BUCKET_EXISTS" = "yes" ]; then
  echo -e "${GREEN}  ✅ S3 bucket '${TF_STATE_BUCKET}' already exists. Skipping.${NC}"
else
  aws s3api create-bucket \
    --bucket "${TF_STATE_BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"

  # Enable versioning
  aws s3api put-bucket-versioning \
    --bucket "${TF_STATE_BUCKET}" \
    --versioning-configuration Status=Enabled

  # Enable encryption
  aws s3api put-bucket-encryption \
    --bucket "${TF_STATE_BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }]
    }'

  # Block public access
  aws s3api put-public-access-block \
    --bucket "${TF_STATE_BUCKET}" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  # Tag bucket
  aws s3api put-bucket-tagging \
    --bucket "${TF_STATE_BUCKET}" \
    --tagging "TagSet=[{Key=Project,Value=${PROJECT}},{Key=ManagedBy,Value=bootstrap},{Key=Purpose,Value=terraform-state}]"

  echo -e "${GREEN}  ✅ S3 bucket '${TF_STATE_BUCKET}' created with versioning + encryption.${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: CREATE DYNAMODB TABLE FOR STATE LOCKING
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[Step 3] Creating DynamoDB table for Terraform state locking...${NC}"

TABLE_EXISTS=$(aws dynamodb describe-table --table-name "${TF_LOCK_TABLE}" --region "${REGION}" 2>/dev/null && echo "yes" || echo "no")

if [ "$TABLE_EXISTS" = "yes" ]; then
  echo -e "${GREEN}  ✅ DynamoDB table '${TF_LOCK_TABLE}' already exists. Skipping.${NC}"
else
  aws dynamodb create-table \
    --table-name "${TF_LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" \
    --tags Key=Project,Value=${PROJECT} Key=ManagedBy,Value=bootstrap \
    --output text --query 'TableDescription.TableArn'

  echo -e "${GREEN}  ✅ DynamoDB table '${TF_LOCK_TABLE}' created.${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: CREATE IAM USER + POLICY FOR TERRAFORM
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[Step 4] Creating IAM user for Terraform...${NC}"

USER_EXISTS=$(aws iam get-user --user-name "${IAM_USER}" 2>/dev/null && echo "yes" || echo "no")

if [ "$USER_EXISTS" = "yes" ]; then
  echo -e "${GREEN}  ✅ IAM user '${IAM_USER}' already exists.${NC}"
else
  aws iam create-user \
    --user-name "${IAM_USER}" \
    --tags Key=Project,Value=${PROJECT} Key=ManagedBy,Value=bootstrap

  echo -e "${GREEN}  ✅ IAM user '${IAM_USER}' created.${NC}"
fi

# Create/Update policy
echo -e "${YELLOW}  Attaching IAM policy...${NC}"

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"
POLICY_EXISTS=$(aws iam get-policy --policy-arn "${POLICY_ARN}" 2>/dev/null && echo "yes" || echo "no")

if [ "$POLICY_EXISTS" = "yes" ]; then
  # Update existing policy (create new version)
  aws iam create-policy-version \
    --policy-arn "${POLICY_ARN}" \
    --policy-document file://iam/sap-workspaces-terraform-policy.json \
    --set-as-default \
    --output text --query 'PolicyVersion.VersionId' 2>/dev/null || true
  echo -e "${GREEN}  ✅ Policy updated.${NC}"
else
  aws iam create-policy \
    --policy-name "${IAM_POLICY_NAME}" \
    --policy-document file://iam/sap-workspaces-terraform-policy.json \
    --description "Terraform policy for SAP Training Lab WorkSpaces deployment" \
    --tags Key=Project,Value=${PROJECT} \
    --output text --query 'Policy.Arn'
  echo -e "${GREEN}  ✅ Policy '${IAM_POLICY_NAME}' created.${NC}"
fi

# Attach policy to user
aws iam attach-user-policy \
  --user-name "${IAM_USER}" \
  --policy-arn "${POLICY_ARN}" 2>/dev/null || true

echo -e "${GREEN}  ✅ Policy attached to user '${IAM_USER}'.${NC}"

# Create access keys (only if none exist)
EXISTING_KEYS=$(aws iam list-access-keys --user-name "${IAM_USER}" --query 'length(AccessKeyMetadata)' --output text)

if [ "$EXISTING_KEYS" = "0" ]; then
  echo ""
  echo -e "${YELLOW}  Creating access keys...${NC}"
  
  KEYS=$(aws iam create-access-key --user-name "${IAM_USER}" --output json)
  
  ACCESS_KEY=$(echo "$KEYS" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
  SECRET_KEY=$(echo "$KEYS" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")
  
  echo ""
  echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  ⚠️  SAVE THESE CREDENTIALS NOW - SHOWN ONLY ONCE!          ║${NC}"
  echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${RED}║  Access Key ID:     ${ACCESS_KEY}                    ║${NC}"
  echo -e "${RED}║  Secret Access Key: ${SECRET_KEY}  ║${NC}"
  echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${RED}║  Configure with:                                            ║${NC}"
  echo -e "${RED}║  aws configure --profile sap-terraform                      ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
else
  echo -e "${GREEN}  ✅ Access keys already exist for '${IAM_USER}'. Skipping key creation.${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: DISCOVER WORKSPACES BUNDLES
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[Step 5] Discovering available WorkSpaces bundles in ${REGION}...${NC}"
echo ""

aws workspaces describe-workspace-bundles \
  --owner "AMAZON" \
  --region "${REGION}" \
  --query 'Bundles[?contains(Name, `Standard`) || contains(Name, `Performance`)].{BundleId:BundleId, Name:Name, Compute:ComputeType.Name, Storage:RootStorage.Capacity}' \
  --output table 2>/dev/null || echo -e "${YELLOW}  ⚠️  Could not list bundles. WorkSpaces may not be available in this region yet.${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6: CHECK SERVICE QUOTAS
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[Step 6] Checking relevant service quotas...${NC}"

echo "  VPCs per region:"
aws service-quotas get-service-quota \
  --service-code vpc \
  --quota-code L-F678F1CE \
  --region "${REGION}" \
  --query 'Quota.Value' \
  --output text 2>/dev/null || echo "  (Could not retrieve - check manually)"

echo "  Elastic IPs per region:"
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-0263D0A3 \
  --region "${REGION}" \
  --query 'Quota.Value' \
  --output text 2>/dev/null || echo "  (Could not retrieve - check manually)"

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                  BOOTSTRAP COMPLETE ✅                       ║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║                                                              ║${NC}"
echo -e "${BLUE}║  Account:         ${AWS_ACCOUNT_ID}                          ║${NC}"
echo -e "${BLUE}║  Region:          ${REGION}                                  ║${NC}"
echo -e "${BLUE}║  State Bucket:    ${TF_STATE_BUCKET}                         ║${NC}"
echo -e "${BLUE}║  Lock Table:      ${TF_LOCK_TABLE}                           ║${NC}"
echo -e "${BLUE}║  IAM User:        ${IAM_USER}                                ║${NC}"
echo -e "${BLUE}║  WorkSpaces Role: workspaces_DefaultRole                     ║${NC}"
echo -e "${BLUE}║                                                              ║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  NEXT STEPS:                                                 ║${NC}"
echo -e "${BLUE}║                                                              ║${NC}"
echo -e "${BLUE}║  1. Configure Terraform AWS profile:                         ║${NC}"
echo -e "${BLUE}║     aws configure --profile sap-terraform                    ║${NC}"
echo -e "${BLUE}║                                                              ║${NC}"
echo -e "${BLUE}║  2. Export profile (or add to provider block):               ║${NC}"
echo -e "${BLUE}║     export AWS_PROFILE=sap-terraform                         ║${NC}"
echo -e "${BLUE}║                                                              ║${NC}"
echo -e "${BLUE}║  3. Initialize Terraform:                                    ║${NC}"
echo -e "${BLUE}║     terraform init                                           ║${NC}"
echo -e "${BLUE}║                                                              ║${NC}"
echo -e "${BLUE}║  4. Deploy POC:                                              ║${NC}"
echo -e "${BLUE}║     terraform apply -var-file=environments/poc.tfvars \\      ║${NC}"
echo -e "${BLUE}║       -var='ad_admin_password=YourP@ssw0rd'                  ║${NC}"
echo -e "${BLUE}║                                                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
