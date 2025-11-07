# -----------------------------------------------------------------------------
# IAM Roles and Policies for AWS Batch with Fargate
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Batch Service Role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "batch_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "batch_service" {
  name               = "${local.name_prefix}-batch-service-role"
  assume_role_policy = data.aws_iam_policy_document.batch_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "batch_service" {
  role       = aws_iam_role.batch_service.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# -----------------------------------------------------------------------------
# Batch Execution Role (for Fargate - pulls images and writes logs)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "batch_execution_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "batch_execution" {
  name               = "${local.name_prefix}-batch-execution-role"
  assume_role_policy = data.aws_iam_policy_document.batch_execution_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "batch_execution" {
  role       = aws_iam_role.batch_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for pulling from ECR and writing logs
data "aws_iam_policy_document" "batch_execution_additional" {
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

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.batch_jobs.arn}:*"
    ]
  }

  # Fargate-specific: Access to Secrets Manager and SSM for secrets
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.project_name}/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters"
    ]

    resources = [
      "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/${var.project_name}/*"
    ]
  }
}

resource "aws_iam_role_policy" "batch_execution_additional" {
  name   = "${local.name_prefix}-batch-execution-additional"
  role   = aws_iam_role.batch_execution.id
  policy = data.aws_iam_policy_document.batch_execution_additional.json
}

# -----------------------------------------------------------------------------
# Batch Job Role (permissions for jobs to access AWS resources)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "batch_job_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "batch_job" {
  name               = "${local.name_prefix}-batch-job-role"
  assume_role_policy = data.aws_iam_policy_document.batch_job_assume_role.json

  tags = local.common_tags
}

# Policy for job to access S3, Secrets Manager, etc.
data "aws_iam_policy_document" "batch_job" {
  # S3 access
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]

    resources = [
      "arn:${local.partition}:s3:::*"
    ]
  }

  # Secrets Manager access
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.project_name}/*"
    ]
  }

  # SSM Parameter Store access
  statement {
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]

    resources = [
      "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/${var.project_name}/*"
    ]
  }

  # CloudWatch Metrics
  statement {
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricData"
    ]

    resources = ["*"]
  }

  # CloudWatch Logs
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.batch_jobs.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "batch_job" {
  name   = "${local.name_prefix}-batch-job-policy"
  role   = aws_iam_role.batch_job.id
  policy = data.aws_iam_policy_document.batch_job.json
}

# -----------------------------------------------------------------------------
# EventBridge Role (for triggering Batch jobs)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "eventbridge_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eventbridge" {
  count = var.enable_eventbridge_schedule ? 1 : 0

  name               = "${local.name_prefix}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "eventbridge" {
  count = var.enable_eventbridge_schedule ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "batch:SubmitJob"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "eventbridge" {
  count = var.enable_eventbridge_schedule ? 1 : 0

  name   = "${local.name_prefix}-eventbridge-policy"
  role   = aws_iam_role.eventbridge[0].id
  policy = data.aws_iam_policy_document.eventbridge[0].json
}

