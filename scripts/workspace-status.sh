#!/bin/bash
###############################################################################
# Script: workspace-status.sh
# Description: Quick status check for all WorkSpaces (for trainer)
# Usage: ./scripts/workspace-status.sh [region]
###############################################################################

REGION=${1:-"ap-south-1"}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         SAP Training Lab - WorkSpaces Status                ║"
echo "║         $(date '+%Y-%m-%d %H:%M:%S %Z')                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Get all workspaces with status
echo "=== Individual WorkSpace Status ==="
aws workspaces describe-workspaces \
  --region "$REGION" \
  --query 'Workspaces[].{Username:UserName, State:State, IP:IpAddress, BundleId:BundleId}' \
  --output table

echo ""
echo "=== Summary ==="
TOTAL=$(aws workspaces describe-workspaces --region "$REGION" --query 'length(Workspaces)' --output text)
RUNNING=$(aws workspaces describe-workspaces --region "$REGION" --query 'length(Workspaces[?State==`AVAILABLE`])' --output text)
STOPPED=$(aws workspaces describe-workspaces --region "$REGION" --query 'length(Workspaces[?State==`STOPPED`])' --output text)
PENDING=$(aws workspaces describe-workspaces --region "$REGION" --query 'length(Workspaces[?State==`PENDING`])' --output text)
ERROR=$(aws workspaces describe-workspaces --region "$REGION" --query 'length(Workspaces[?State==`ERROR`])' --output text)

echo "  Total:    $TOTAL"
echo "  Running:  $RUNNING"
echo "  Stopped:  $STOPPED"
echo "  Pending:  $PENDING"
echo "  Error:    $ERROR"
echo ""

# Cost estimate for running workspaces
if [ "$RUNNING" -gt 0 ]; then
  HOURLY_COST=$(echo "$RUNNING * 0.22" | bc)
  echo "  💰 Current hourly cost (running): \$$HOURLY_COST/hr"
fi

echo ""
echo "=== Quick Actions ==="
echo "  Stop all:  aws workspaces stop-workspaces --stop-workspace-requests \$(aws workspaces describe-workspaces --region $REGION --query 'Workspaces[?State==\`AVAILABLE\`].{WorkspaceId:WorkspaceId}' --output json)"
echo "  Start all: aws workspaces start-workspaces --start-workspace-requests \$(aws workspaces describe-workspaces --region $REGION --query 'Workspaces[?State==\`STOPPED\`].{WorkspaceId:WorkspaceId}' --output json)"
