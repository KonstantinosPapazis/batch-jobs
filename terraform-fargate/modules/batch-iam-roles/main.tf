# -----------------------------------------------------------------------------
# Reusable IAM Roles Module for AWS Batch Teams
# -----------------------------------------------------------------------------
# This module creates a shared set of IAM roles for a team's batch jobs
# Use this to avoid creating separate roles for each job definition
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"
}

locals {
  team_prefix = "${var.project_name}-${var.team_name}-${var.environment}"
  
  # Common tags
  common_tags = merge(
    {
      Team        = var.team_name
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Batch Execution Role (for pulling images and writing logs)
# Shared by all jobs in the team
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "execution_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.team_prefix}-batch-execution-role"
  description        = "Execution role for ${var.team_name} team batch jobs"
  assume_role_policy = data.aws_iam_policy_document.execution_assume_role.json

  tags = local.common_tags
}

# Attach standard ECS Task Execution policy
resource "aws_iam_role_policy_attachment" "execution_standard" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional execution permissions
data "aws_iam_policy_document" "execution_additional" {
  # ECR permissions
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }

  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/batch/${var.project_name}*:*"
    ]
  }

  # Secrets Manager (for pulling secrets during task startup)
  dynamic "statement" {
    for_each = var.enable_secrets_manager ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue"
      ]
      resources = [
        "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project_name}/${var.team_name}/*"
      ]
    }
  }

  # SSM Parameter Store (for pulling parameters during task startup)
  dynamic "statement" {
    for_each = var.enable_ssm_parameters ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      resources = [
        "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/${var.team_name}/*"
      ]
    }
  }
}

resource "aws_iam_role_policy" "execution_additional" {
  name   = "${local.team_prefix}-execution-additional"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_additional.json
}

# -----------------------------------------------------------------------------
# Batch Job Role (permissions for job application logic)
# Shared by all jobs in the team
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "job_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "job" {
  name               = "${local.team_prefix}-batch-job-role"
  description        = "Job role for ${var.team_name} team batch jobs"
  assume_role_policy = data.aws_iam_policy_document.job_assume_role.json

  tags = local.common_tags
}

# Base job permissions
data "aws_iam_policy_document" "job_base" {
  # S3 access - scoped to team's buckets/prefixes
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = var.s3_resources
  }

  # Secrets Manager access - scoped to team
  dynamic "statement" {
    for_each = var.enable_secrets_manager ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      resources = [
        "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project_name}/${var.team_name}/*"
      ]
    }
  }

  # SSM Parameter Store access - scoped to team
  dynamic "statement" {
    for_each = var.enable_ssm_parameters ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]
      resources = [
        "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/${var.team_name}/*"
      ]
    }
  }

  # CloudWatch Metrics
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["${var.project_name}/${var.team_name}"]
    }
  }

  # CloudWatch Logs (for application logging)
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/batch/${var.project_name}*:*"
    ]
  }

  # DynamoDB access (if enabled)
  dynamic "statement" {
    for_each = var.enable_dynamodb ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      resources = var.dynamodb_table_arns
    }
  }

  # SQS access (if enabled)
  dynamic "statement" {
    for_each = var.enable_sqs ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      resources = var.sqs_queue_arns
    }
  }

  # SNS access (if enabled)
  dynamic "statement" {
    for_each = var.enable_sns ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "sns:Publish"
      ]
      resources = var.sns_topic_arns
    }
  }
}

resource "aws_iam_role_policy" "job_base" {
  name   = "${local.team_prefix}-job-base-permissions"
  role   = aws_iam_role.job.id
  policy = data.aws_iam_policy_document.job_base.json
}

# Custom additional policies (if provided)
resource "aws_iam_role_policy" "job_custom" {
  count = var.custom_job_policy_json != "" ? 1 : 0

  name   = "${local.team_prefix}-job-custom-permissions"
  role   = aws_iam_role.job.id
  policy = var.custom_job_policy_json
}

# Attach managed policies (if provided)
resource "aws_iam_role_policy_attachment" "job_managed" {
  count = length(var.managed_policy_arns)

  role       = aws_iam_role.job.name
  policy_arn = var.managed_policy_arns[count.index]
}

