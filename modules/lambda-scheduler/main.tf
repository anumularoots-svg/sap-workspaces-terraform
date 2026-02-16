###############################################################################
# MODULE: LAMBDA SCHEDULER
# EventBridge + Lambda for automated bulk start/stop of WorkSpaces
#  - End-of-Day Stop: Force stop all WorkSpaces at 8 PM IST
#  - Morning Start (optional): Pre-start all WorkSpaces before class
###############################################################################

# ─────────────────────────────────────────────────────────────────────────────
# IAM ROLE FOR LAMBDA
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_workspaces" {
  name = "${var.project_name}-${var.environment}-ws-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ws-scheduler-role"
  }
}

resource "aws_iam_role_policy" "lambda_workspaces" {
  name = "${var.project_name}-${var.environment}-ws-scheduler-policy"
  role = aws_iam_role.lambda_workspaces.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "workspaces:DescribeWorkspaces",
          "workspaces:StopWorkspaces",
          "workspaces:StartWorkspaces",
          "workspaces:DescribeWorkspaceDirectories"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# LAMBDA FUNCTION: END-OF-DAY STOP
# ─────────────────────────────────────────────────────────────────────────────
data "archive_file" "eod_stop" {
  type        = "zip"
  output_path = "${path.module}/lambda_eod_stop.zip"

  source {
    content  = <<-PYTHON
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Stop all running WorkSpaces at end of day."""
    client = boto3.client('workspaces')
    
    # Get all workspaces
    workspaces = []
    paginator = client.get_paginator('describe_workspaces')
    for page in paginator.paginate():
        workspaces.extend(page['Workspaces'])
    
    # Filter running workspaces (state = AVAILABLE means running)
    running = [ws for ws in workspaces if ws['State'] == 'AVAILABLE']
    
    if not running:
        logger.info("No running WorkSpaces to stop.")
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'No running WorkSpaces', 'stopped': 0})
        }
    
    # Stop in batches of 25 (API limit)
    stopped_count = 0
    for i in range(0, len(running), 25):
        batch = running[i:i+25]
        stop_requests = [{'WorkspaceId': ws['WorkspaceId']} for ws in batch]
        
        response = client.stop_workspaces(StopWorkspaceRequests=stop_requests)
        
        # Log any failures
        for fail in response.get('FailedRequests', []):
            logger.error(f"Failed to stop {fail['WorkspaceId']}: {fail.get('ErrorMessage', 'Unknown error')}")
        
        stopped_count += len(batch) - len(response.get('FailedRequests', []))
    
    logger.info(f"Successfully stopped {stopped_count} WorkSpaces")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Stopped {stopped_count} WorkSpaces',
            'stopped': stopped_count,
            'total_running': len(running)
        })
    }
    PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "eod_stop" {
  function_name    = "${var.project_name}-${var.environment}-eod-stop"
  filename         = data.archive_file.eod_stop.output_path
  source_code_hash = data.archive_file.eod_stop.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 120
  memory_size      = 128
  role             = aws_iam_role.lambda_workspaces.arn

  environment {
    variables = {
      REGION = var.aws_region
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eod-stop"
  }
}

resource "aws_cloudwatch_log_group" "eod_stop" {
  name              = "/aws/lambda/${aws_lambda_function.eod_stop.function_name}"
  retention_in_days = 14
}

# EventBridge Rule - End of Day
resource "aws_cloudwatch_event_rule" "eod_stop" {
  name                = "${var.project_name}-${var.environment}-eod-stop"
  description         = "Stop all WorkSpaces at end of day (8 PM IST)"
  schedule_expression = var.eod_stop_schedule

  tags = {
    Name = "${var.project_name}-${var.environment}-eod-stop-rule"
  }
}

resource "aws_cloudwatch_event_target" "eod_stop" {
  rule      = aws_cloudwatch_event_rule.eod_stop.name
  target_id = "eod-stop-workspaces"
  arn       = aws_lambda_function.eod_stop.arn
}

resource "aws_lambda_permission" "eod_stop" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.eod_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.eod_stop.arn
}

# ─────────────────────────────────────────────────────────────────────────────
# LAMBDA FUNCTION: MORNING START (Optional)
# ─────────────────────────────────────────────────────────────────────────────
data "archive_file" "morning_start" {
  count = var.enable_morning_start ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda_morning_start.zip"

  source {
    content  = <<-PYTHON
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Start all stopped WorkSpaces before class begins."""
    client = boto3.client('workspaces')
    
    # Get all workspaces
    workspaces = []
    paginator = client.get_paginator('describe_workspaces')
    for page in paginator.paginate():
        workspaces.extend(page['Workspaces'])
    
    # Filter stopped workspaces
    stopped = [ws for ws in workspaces if ws['State'] == 'STOPPED']
    
    if not stopped:
        logger.info("No stopped WorkSpaces to start.")
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'No stopped WorkSpaces', 'started': 0})
        }
    
    # Start in batches of 25 (API limit)
    started_count = 0
    for i in range(0, len(stopped), 25):
        batch = stopped[i:i+25]
        start_requests = [{'WorkspaceId': ws['WorkspaceId']} for ws in batch]
        
        response = client.start_workspaces(StartWorkspaceRequests=start_requests)
        
        for fail in response.get('FailedRequests', []):
            logger.error(f"Failed to start {fail['WorkspaceId']}: {fail.get('ErrorMessage', 'Unknown error')}")
        
        started_count += len(batch) - len(response.get('FailedRequests', []))
    
    logger.info(f"Successfully started {started_count} WorkSpaces")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Started {started_count} WorkSpaces',
            'started': started_count,
            'total_stopped': len(stopped)
        })
    }
    PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "morning_start" {
  count = var.enable_morning_start ? 1 : 0

  function_name    = "${var.project_name}-${var.environment}-morning-start"
  filename         = data.archive_file.morning_start[0].output_path
  source_code_hash = data.archive_file.morning_start[0].output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 120
  memory_size      = 128
  role             = aws_iam_role.lambda_workspaces.arn

  environment {
    variables = {
      REGION = var.aws_region
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-morning-start"
  }
}

resource "aws_cloudwatch_log_group" "morning_start" {
  count = var.enable_morning_start ? 1 : 0

  name              = "/aws/lambda/${aws_lambda_function.morning_start[0].function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_event_rule" "morning_start" {
  count = var.enable_morning_start ? 1 : 0

  name                = "${var.project_name}-${var.environment}-morning-start"
  description         = "Start all WorkSpaces before class (9:30 AM IST)"
  schedule_expression = var.morning_start_schedule
}

resource "aws_cloudwatch_event_target" "morning_start" {
  count = var.enable_morning_start ? 1 : 0

  rule      = aws_cloudwatch_event_rule.morning_start[0].name
  target_id = "morning-start-workspaces"
  arn       = aws_lambda_function.morning_start[0].arn
}

resource "aws_lambda_permission" "morning_start" {
  count = var.enable_morning_start ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.morning_start[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.morning_start[0].arn
}

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────────────────────
variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "eod_stop_schedule" { type = string }
variable "morning_start_schedule" { type = string }
variable "enable_morning_start" { type = bool }

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────
output "eod_stop_lambda_arn" {
  description = "ARN of the EOD stop Lambda"
  value       = aws_lambda_function.eod_stop.arn
}

output "morning_start_lambda_arn" {
  description = "ARN of the morning start Lambda"
  value       = var.enable_morning_start ? aws_lambda_function.morning_start[0].arn : null
}
