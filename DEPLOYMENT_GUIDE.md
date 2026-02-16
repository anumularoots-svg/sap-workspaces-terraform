# SAP Training Lab - Step-by-Step Deployment Guide
## AWS Account: 657246200133 | Region: ap-south-1 (Mumbai)

---

## PHASE 0: Prerequisites Checklist

Before starting, ensure you have:

- [ ] AWS CLI v2 installed (`aws --version`)
- [ ] Terraform >= 1.5.0 installed (`terraform --version`)
- [ ] AWS root/admin credentials configured (`aws configure`)
- [ ] Git installed (`git --version`)

### Verify AWS Connection
```bash
aws sts get-caller-identity
# Expected output should show Account: 657246200133
```

---

## PHASE 1: Bootstrap (One-Time Setup — ~5 minutes)

### Step 1.1: Clone/Extract the project
```bash
unzip sap-workspaces-terraform.zip
cd sap-workspaces-terraform
chmod +x scripts/*.sh
```

### Step 1.2: Run Bootstrap Script
This creates IAM user, S3 state bucket, DynamoDB lock table, and workspaces_DefaultRole.

```bash
./scripts/bootstrap.sh
```

**What it creates in account 657246200133:**

| Resource | Name | Purpose |
|----------|------|---------|
| S3 Bucket | `lanciere-terraform-state-657246200133` | Terraform state storage |
| DynamoDB Table | `terraform-lock` | State locking |
| IAM User | `terraform-sap-workspaces` | Terraform execution user |
| IAM Policy | `SAPWorkSpacesTerraformPolicy` | Scoped permissions |
| IAM Role | `workspaces_DefaultRole` | AWS WorkSpaces service role |

### Step 1.3: Configure Terraform AWS Profile
```bash
# Use the access keys shown by bootstrap.sh
aws configure --profile sap-terraform
# AWS Access Key ID: <from bootstrap output>
# AWS Secret Access Key: <from bootstrap output>
# Default region: ap-south-1
# Default output: json

# Set as active profile
export AWS_PROFILE=sap-terraform
```

### Step 1.4: Discover Available Bundles
```bash
./scripts/discover-bundles.sh ap-south-1
```
Note the correct `BundleId` for Standard Linux and update `environments/poc.tfvars` if different from `wsb-clj85qzj1`.

---

## PHASE 2: POC Deployment (2 WorkSpaces — ~20 minutes)

### Step 2.1: Initialize Terraform
```bash
terraform init -backend-config="backend.hcl"
```

Expected output:
```
Terraform has been successfully initialized!
```

### Step 2.2: Review the Plan
```bash
terraform plan \
  -var-file="environments/poc.tfvars" \
  -var="ad_admin_password=YourSecureP@ssw0rd123"
```

Expected: ~25-30 resources to be created. Review carefully.

### Step 2.3: Deploy POC
```bash
terraform apply \
  -var-file="environments/poc.tfvars" \
  -var="ad_admin_password=YourSecureP@ssw0rd123"
```

Type `yes` when prompted. This takes **15-20 minutes** (Directory Service + WorkSpaces provisioning).

### Step 2.4: Capture Outputs
```bash
# Get registration code (students need this)
terraform output workspace_registration_code

# Get all workspace IDs
terraform output workspace_ids

# Get CloudWatch dashboard URL
terraform output cloudwatch_dashboard_url

# Get full connection instructions
terraform output student_connection_instructions
```

### Step 2.5: Verify Everything
```bash
./scripts/workspace-status.sh
```

---

## PHASE 3: POC Testing (~1 hour)

### Test 1: Student Login Flow
1. Download WorkSpaces client: https://clients.amazonworkspaces.com/
2. Enter the **registration code** from Step 2.4
3. Login as `student01` / `YourSecureP@ssw0rd123`
4. Verify desktop loads successfully

### Test 2: Auto-Stop (10 min idle)
1. Login to WorkSpace
2. Leave it idle for 10 minutes (no mouse/keyboard)
3. Verify WorkSpace transitions to STOPPED:
   ```bash
   watch -n 30 './scripts/workspace-status.sh'
   ```

### Test 3: Self-Service Start
1. After auto-stop, open WorkSpaces client again
2. Click the **"Start"** button
3. Verify WorkSpace boots within 2-3 minutes

### Test 4: EOD Lambda (Bulk Stop)
```bash
# Manually invoke the Lambda to test
aws lambda invoke \
  --function-name sap-training-lab-poc-eod-stop \
  --region ap-south-1 \
  /tmp/lambda-output.json

cat /tmp/lambda-output.json
```

### Test 5: Install SAP Software
1. Login to student01 WorkSpace
2. Install SAP GUI, HANA Studio, PuTTY, etc.
3. Verify all tools work
4. **Create custom bundle** (AWS Console):
   - WorkSpaces → Select student01 → Actions → **Create Bundle**
   - Name: `SAP-Basis-Training-Bundle`
   - Note the new Bundle ID

### Test 6: Demo to SAP Trainer
- Walk through entire flow
- Show CloudWatch dashboard
- Get sign-off

---

## PHASE 4: Production Deployment (40 WorkSpaces — ~45 minutes)

### Step 4.1: Update Bundle ID (if custom bundle created)
Edit `environments/prod.tfvars`:
```hcl
workspace_bundle_id = "wsb-YOURNEWBUNDLEID"  # Custom SAP bundle
```

### Step 4.2: Update Alarm Email
Edit `environments/prod.tfvars`:
```hcl
alarm_email = "your-actual-email@lancieretech.com"
```

### Step 4.3: Deploy Production
```bash
terraform plan \
  -var-file="environments/prod.tfvars" \
  -var="ad_admin_password=YourSecureP@ssw0rd123"

terraform apply \
  -var-file="environments/prod.tfvars" \
  -var="ad_admin_password=YourSecureP@ssw0rd123"
```

This takes **30-45 minutes** for 40 WorkSpaces.

### Step 4.4: Verify All 40 WorkSpaces
```bash
./scripts/workspace-status.sh

# Should show 40 workspaces in AVAILABLE state
```

### Step 4.5: Confirm SNS Subscription
Check your email and **confirm the SNS subscription** link to receive alerts.

### Step 4.6: Generate Student Credentials Sheet
```bash
# Quick credential list
for i in $(seq -f "%02g" 1 40); do
  echo "student${i} | Password: <distributed-separately> | Registration Code: $(terraform output -raw workspace_registration_code)"
done
```

---

## PHASE 5: Ongoing Operations

### Daily Monitoring
```bash
# Check status
./scripts/workspace-status.sh

# CloudWatch Dashboard (bookmark this URL)
terraform output cloudwatch_dashboard_url
```

### Manual Bulk Operations
```bash
# Stop ALL running workspaces immediately
aws workspaces describe-workspaces --region ap-south-1 \
  --query 'Workspaces[?State==`AVAILABLE`].WorkspaceId' --output text | \
  tr '\t' '\n' | while read WS_ID; do
    echo "Stopping $WS_ID"
    aws workspaces stop-workspaces --stop-workspace-requests WorkspaceId=$WS_ID --region ap-south-1
  done

# Start ALL stopped workspaces
aws workspaces describe-workspaces --region ap-south-1 \
  --query 'Workspaces[?State==`STOPPED`].WorkspaceId' --output text | \
  tr '\t' '\n' | while read WS_ID; do
    echo "Starting $WS_ID"
    aws workspaces start-workspaces --start-workspace-requests WorkspaceId=$WS_ID --region ap-south-1
  done
```

### When Training Batch Ends
```bash
# Destroy everything
./scripts/cleanup.sh prod
```

---

## Quick Reference Card

| Item | Value |
|------|-------|
| AWS Account | `657246200133` |
| Region | `ap-south-1` (Mumbai) |
| VPC CIDR | `10.0.0.0/16` |
| Directory | `sap-lab.local` (Simple AD) |
| Students | `student01` through `student40` |
| Auto-Stop | 10 minutes idle |
| EOD Shutdown | 8:00 PM IST (Mon-Fri) |
| Morning Start | 9:30 AM IST (Mon-Fri, if enabled) |
| State Bucket | `lanciere-terraform-state-657246200133` |
| Dashboard | CloudWatch → sap-training-lab-prod-workspaces |
