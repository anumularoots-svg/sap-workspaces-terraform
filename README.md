# SAP Training Lab — AWS WorkSpaces Infrastructure

Terraform automation for provisioning AWS WorkSpaces for SAP Basis training (40 students) with auto-stop on idle, self-service start, and cost optimization.

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│ AWS Cloud (ap-south-1)                                        │
│                                                               │
│  ┌─────────────┐     ┌──────────────────────────────────────┐ │
│  │ Simple AD    │────▶│ VPC (10.0.0.0/16)                    │ │
│  │ (sap-lab.    │     │                                      │ │
│  │  local)      │     │  Private Subnets:                    │ │
│  └─────────────┘     │   ├── 10.0.1.0/24 (AZ-a) ─ WS 1-20  │ │
│                      │   └── 10.0.2.0/24 (AZ-b) ─ WS 21-40 │ │
│  ┌─────────────┐     │                                      │ │
│  │ EventBridge  │     │  Public Subnets:                     │ │
│  │ + Lambda     │     │   └── NAT Gateway (internet access)  │ │
│  │ (Scheduler)  │     └──────────────────────────────────────┘ │
│  └─────────────┘                                              │
│                      ┌──────────────────────────────────────┐ │
│  ┌─────────────┐     │ CloudWatch Dashboard                  │ │
│  │ SNS Alerts  │◀────│ + Alarms (unhealthy, conn failures)   │ │
│  └─────────────┘     └──────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites
- AWS CLI v2 configured with appropriate permissions
- Terraform >= 1.5.0
- AWS account with WorkSpaces service access

### Step 1: Discover available bundles
```bash
chmod +x scripts/*.sh
./scripts/discover-bundles.sh ap-south-1
```

### Step 2: Initialize Terraform
```bash
terraform init
```

### Step 3: Deploy POC (2 WorkSpaces — Free Tier)
```bash
terraform plan -var-file="environments/poc.tfvars" -var="ad_admin_password=YourP@ssw0rd123"
terraform apply -var-file="environments/poc.tfvars" -var="ad_admin_password=YourP@ssw0rd123"
```

### Step 4: Validate & test the flow
```bash
./scripts/workspace-status.sh
```

### Step 5: Scale to production (40 WorkSpaces)
```bash
terraform plan -var-file="environments/prod.tfvars" -var="ad_admin_password=YourP@ssw0rd123"
terraform apply -var-file="environments/prod.tfvars" -var="ad_admin_password=YourP@ssw0rd123"
```

## Project Structure
```
sap-workspaces-terraform/
├── main.tf                          # Root module — orchestrates everything
├── variables.tf                     # All input variables
├── outputs.tf                       # All outputs
├── environments/
│   ├── poc.tfvars                   # POC: 2 WorkSpaces (Free Tier)
│   └── prod.tfvars                  # Production: 40 WorkSpaces
├── modules/
│   ├── vpc/                         # VPC, subnets, NAT, routing
│   ├── directory/                   # Simple AD for user auth
│   ├── workspaces/                  # WorkSpaces + security groups
│   ├── lambda-scheduler/            # EventBridge + Lambda (start/stop)
│   └── monitoring/                  # CloudWatch dashboard + alarms
├── scripts/
│   ├── discover-bundles.sh          # Find available WS bundles
│   └── workspace-status.sh          # Trainer status dashboard
└── README.md
```

## Key Features

| Feature | Implementation |
|---------|---------------|
| Auto-Stop (10 min idle) | `running_mode = AUTO_STOP`, timeout = 10 min |
| Self-Service Start | WorkSpaces directory self-service permissions |
| End-of-Day Bulk Stop | Lambda + EventBridge (8 PM IST, Mon-Fri) |
| Morning Pre-Start | Optional Lambda (9:30 AM IST, Mon-Fri) |
| Monitoring | CloudWatch dashboard + SNS alarms |
| Cost Optimization | AutoStop + scheduled stop + no admin for students |

## Cost Estimate

| Phase | Config | Monthly Cost |
|-------|--------|-------------|
| POC | 2 WorkSpaces | ~$37 (directory only, WS free for 2 months) |
| Production | 40 WorkSpaces | ~$1,700 (with 6 hrs/day usage) |

## Cleanup
```bash
terraform destroy -var-file="environments/poc.tfvars" -var="ad_admin_password=YourP@ssw0rd123"
```
