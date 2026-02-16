###############################################################################
# MODULE: MONITORING
# CloudWatch Dashboard + Alarms for WorkSpaces
###############################################################################

# ─────────────────────────────────────────────────────────────────────────────
# SNS TOPIC FOR ALERTS
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  count = var.alarm_email != "" ? 1 : 0
  name  = "${var.project_name}-${var.environment}-ws-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH DASHBOARD
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "workspaces" {
  dashboard_name = "${var.project_name}-${var.environment}-workspaces"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/WorkSpaces", "Available", "DirectoryId", var.directory_id],
            ["AWS/WorkSpaces", "Stopped", "DirectoryId", var.directory_id],
            ["AWS/WorkSpaces", "Maintenance", "DirectoryId", var.directory_id],
            ["AWS/WorkSpaces", "Unhealthy", "DirectoryId", var.directory_id],
          ]
          view    = "timeSeries"
          stacked = true
          region  = var.aws_region
          title   = "WorkSpaces Status Overview"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/WorkSpaces", "ConnectionAttempt", "DirectoryId", var.directory_id],
            ["AWS/WorkSpaces", "ConnectionSuccess", "DirectoryId", var.directory_id],
            ["AWS/WorkSpaces", "ConnectionFailure", "DirectoryId", var.directory_id],
          ]
          view   = "timeSeries"
          region = var.aws_region
          title  = "Connection Metrics"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/WorkSpaces", "SessionLaunchTime", "DirectoryId", var.directory_id, { stat = "Average" }],
          ]
          view   = "timeSeries"
          region = var.aws_region
          title  = "Average Session Launch Time"
          period = 300
        }
      },
      {
        type   = "text"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          markdown = <<-EOT
            ## SAP Training Lab - Quick Reference
            
            **Total Students:** ${var.student_count}
            **Auto-Stop:** 10 min idle timeout
            **EOD Bulk Stop:** 8:00 PM IST (Mon-Fri)
            
            ### Useful CLI Commands
            ```
            # List all WorkSpaces status
            aws workspaces describe-workspaces --query 'Workspaces[].{User:UserName,State:State,IP:IpAddress}' --output table
            
            # Force stop a specific workspace
            aws workspaces stop-workspaces --stop-workspace-requests WorkspaceId=ws-xxxxx
            
            # Start a specific workspace
            aws workspaces start-workspaces --start-workspace-requests WorkspaceId=ws-xxxxx
            ```
          EOT
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH ALARMS
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "unhealthy_workspaces" {
  count = var.alarm_email != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-unhealthy-workspaces"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Unhealthy"
  namespace           = "AWS/WorkSpaces"
  period              = 300
  statistic           = "Maximum"
  threshold           = 5
  alarm_description   = "More than 5 WorkSpaces are unhealthy"

  dimensions = {
    DirectoryId = var.directory_id
  }

  alarm_actions = [aws_sns_topic.alerts[0].arn]
  ok_actions    = [aws_sns_topic.alerts[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "connection_failures" {
  count = var.alarm_email != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-connection-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ConnectionFailure"
  namespace           = "AWS/WorkSpaces"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "High number of connection failures"

  dimensions = {
    DirectoryId = var.directory_id
  }

  alarm_actions = [aws_sns_topic.alerts[0].arn]
}

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────────────────────
variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "directory_id" { type = string }
variable "student_count" { type = number }
variable "alarm_email" { type = string }

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────
output "dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-${var.environment}-workspaces"
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = var.alarm_email != "" ? aws_sns_topic.alerts[0].arn : null
}
