###############################################################################
# MODULE: USER PROVISIONER
# Creates student users in Simple AD directory via LDAP
# Runs as Lambda inside the VPC with access to directory DNS
###############################################################################

# ─────────────────────────────────────────────────────────────────────────────
# LAMBDA LAYER (ldap3 library)
# ─────────────────────────────────────────────────────────────────────────────
resource "terraform_data" "build_ldap_layer" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p /tmp/ldap-layer/python
      pip3 install ldap3 pyasn1 -t /tmp/ldap-layer/python --quiet 2>/dev/null || \
        pip install ldap3 pyasn1 -t /tmp/ldap-layer/python --quiet --break-system-packages
      cd /tmp/ldap-layer && zip -r /tmp/ldap-layer.zip python -q
    EOT
  }
}

resource "aws_lambda_layer_version" "ldap3" {
  filename            = "/tmp/ldap-layer.zip"
  layer_name          = "${var.project_name}-${var.environment}-ldap3"
  compatible_runtimes = ["python3.12"]
  description         = "ldap3 library for Simple AD user management"

  depends_on = [terraform_data.build_ldap_layer]
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUP FOR LAMBDA (needs LDAP access to directory)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "user_provisioner" {
  name_prefix = "${var.project_name}-${var.environment}-user-prov-"
  vpc_id      = var.vpc_id
  description = "Lambda SG for LDAP access to Simple AD"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-user-provisioner-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM ROLE FOR LAMBDA
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "user_provisioner" {
  name = "${var.project_name}-${var.environment}-user-provisioner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "user_provisioner" {
  name = "${var.project_name}-${var.environment}-user-provisioner-policy"
  role = aws_iam_role.user_provisioner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# LAMBDA FUNCTION - USER PROVISIONER
# ─────────────────────────────────────────────────────────────────────────────
data "archive_file" "user_provisioner" {
  type        = "zip"
  output_path = "${path.module}/user_provisioner.zip"

  source {
    content  = <<-PYTHON
import json
import logging
import ldap3
from ldap3 import Server, Connection, ALL, NTLM, MODIFY_REPLACE

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Create student users in Simple AD via LDAP."""
    
    directory_dns = event['directory_dns_ips']
    directory_name = event['directory_name']
    admin_password = event['admin_password']
    students = event['students']  # list of {username, first_name, last_name, password}
    
    # Parse domain components for LDAP
    domain_parts = directory_name.split('.')
    base_dn = ','.join([f'DC={p}' for p in domain_parts])
    users_dn = f'CN=Users,{base_dn}'
    admin_dn = f'Administrator@{directory_name}'
    
    results = {'created': [], 'existing': [], 'failed': []}
    
    # Connect to Simple AD
    server = Server(directory_dns[0], get_info=ALL, use_ssl=False)
    
    try:
        conn = Connection(
            server,
            user=admin_dn,
            password=admin_password,
            authentication=NTLM,
            auto_bind=True
        )
        logger.info(f"Connected to directory: {directory_name}")
    except Exception as e:
        logger.error(f"Failed to connect to directory: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'LDAP connection failed: {str(e)}'})
        }
    
    for student in students:
        username = student['username']
        user_dn = f'CN={username},{users_dn}'
        
        try:
            # Check if user already exists
            conn.search(users_dn, f'(sAMAccountName={username})', attributes=['cn'])
            
            if conn.entries:
                logger.info(f"User {username} already exists. Skipping.")
                results['existing'].append(username)
                continue
            
            # Create user
            user_attrs = {
                'objectClass': ['top', 'person', 'organizationalPerson', 'user'],
                'cn': username,
                'sAMAccountName': username,
                'userPrincipalName': f'{username}@{directory_name}',
                'givenName': student.get('first_name', 'Student'),
                'sn': student.get('last_name', username),
                'displayName': f"{student.get('first_name', 'Student')} {student.get('last_name', username)}",
                'userAccountControl': '544',  # Normal account + password not required initially
            }
            
            success = conn.add(user_dn, attributes=user_attrs)
            
            if success:
                # Set password
                pwd = student.get('password', 'Student@2026')
                encoded_pwd = f'"{pwd}"'.encode('utf-16-le')
                conn.modify(user_dn, {
                    'unicodePwd': [(MODIFY_REPLACE, [encoded_pwd])]
                })
                
                # Enable account (set userAccountControl to 512 = normal account)
                conn.modify(user_dn, {
                    'userAccountControl': [(MODIFY_REPLACE, ['512'])]
                })
                
                logger.info(f"Created user: {username}")
                results['created'].append(username)
            else:
                logger.error(f"Failed to create {username}: {conn.result}")
                results['failed'].append({'username': username, 'error': str(conn.result)})
                
        except Exception as e:
            logger.error(f"Error creating {username}: {str(e)}")
            results['failed'].append({'username': username, 'error': str(e)})
    
    conn.unbind()
    
    return {
        'statusCode': 200,
        'body': json.dumps(results)
    }
    PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "user_provisioner" {
  function_name    = "${var.project_name}-${var.environment}-user-provisioner"
  filename         = data.archive_file.user_provisioner.output_path
  source_code_hash = data.archive_file.user_provisioner.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 256
  role             = aws_iam_role.user_provisioner.arn

  layers = [aws_lambda_layer_version.ldap3.arn]

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.user_provisioner.id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-user-provisioner"
  }
}

resource "aws_cloudwatch_log_group" "user_provisioner" {
  name              = "/aws/lambda/${aws_lambda_function.user_provisioner.function_name}"
  retention_in_days = 7
}

# ─────────────────────────────────────────────────────────────────────────────
# INVOKE LAMBDA TO CREATE USERS
# ─────────────────────────────────────────────────────────────────────────────
locals {
  students_payload = [
    for i in range(1, var.student_count + 1) : {
      username   = format("%s%02d", var.student_prefix, i)
      first_name = "Student"
      last_name  = format("%02d", i)
      password   = var.student_default_password
    }
  ]
}

resource "terraform_data" "create_users" {
  triggers_replace = [
    var.student_count,
    var.directory_id
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting 60 seconds for Lambda VPC networking..."
      sleep 60
      
      echo "Invoking user provisioner Lambda..."
      aws lambda invoke \
        --function-name ${aws_lambda_function.user_provisioner.function_name} \
        --payload '${jsonencode({
          directory_dns_ips    = var.directory_dns_ips
          directory_name       = var.directory_name
          admin_password       = var.admin_password
          students             = local.students_payload
        })}' \
        --region ${var.aws_region} \
        --cli-read-timeout 300 \
        /tmp/user-provisioner-output.json
      
      echo "Lambda output:"
      cat /tmp/user-provisioner-output.json
    EOT
  }

  depends_on = [aws_lambda_function.user_provisioner]
}

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────────────────────
variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "directory_id" { type = string }
variable "directory_dns_ips" { type = list(string) }
variable "directory_name" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "student_count" { type = number }
variable "student_prefix" { type = string }
variable "student_default_password" { type = string }

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────
output "lambda_function_name" {
  value = aws_lambda_function.user_provisioner.function_name
}
