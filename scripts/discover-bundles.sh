#!/bin/bash
###############################################################################
# Script: discover-bundles.sh
# Description: Discover available WorkSpaces bundles in your region
# Usage: ./scripts/discover-bundles.sh [region]
###############################################################################

REGION=${1:-"ap-south-1"}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Discovering WorkSpaces Bundles in $REGION           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "=== Amazon-Provided Bundles ==="
aws workspaces describe-workspace-bundles \
  --owner "AMAZON" \
  --region "$REGION" \
  --query 'Bundles[].{BundleId:BundleId, Name:Name, ComputeType:ComputeType.Name, RootStorage:RootStorage.Capacity, UserStorage:UserStorage.Capacity, OS:Description}' \
  --output table 2>/dev/null

if [ $? -ne 0 ]; then
  echo "Error: Unable to query bundles. Ensure AWS CLI is configured."
  echo "Run: aws configure"
  exit 1
fi

echo ""
echo "=== Recommended Bundles for SAP Training ==="
echo ""
echo "Linux Standard (2 vCPU, 4 GB):  Budget-friendly for SAP GUI access"
echo "Linux Performance (2 vCPU, 7.5 GB): Better for HANA Studio + SAP GUI"
echo "Windows Standard (2 vCPU, 4 GB): If Windows-specific SAP tools needed"
echo ""
echo "To use a specific bundle, copy its BundleId into your .tfvars file:"
echo '  workspace_bundle_id = "wsb-xxxxxxxxx"'
