# -----------------------------------------------------------------------------
# Using Existing ECS Cluster for Scheduled Batch Jobs
# Alternative to AWS Batch when you want to use your existing cluster
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Approach    = "ECS-Scheduled-Tasks"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources - Reference Existing Resources
# -----------------------------------------------------------------------------

# Reference your existing ECS cluster
data "aws_ecs_cluster" "existing" {
  cluster_name = var.existing_cluster_name
}

# Reference existing VPC (if needed)
data "aws_vpc" "existing" {
  count = var.existing_vpc_id != "" ? 1 : 0
  id    = var.existing_vpc_id
}

# Reference existing subnets (if needed)
data "aws_subnets" "existing" {
  count = var.existing_vpc_id != "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.existing_vpc_id]
  }

  tags = var.subnet_tags
}

# -----------------------------------------------------------------------------
# ECR Repository (Optional - if you don't have one)
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "batch_job" {
  count = var.create_ecr_repository ? 1 : 0

  name                 = "${var.project_name}-${var.environment}-scheduled-job"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy {
    policy = jsonencode({
      rules = [{
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }]
    })
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "scheduled_tasks" {
  name              = "/ecs/${var.project_name}-${var.environment}-scheduled-tasks"
  retention_in_days = var.log_retention_days
}

# -----------------------------------------------------------------------------
# IAM Roles
# -----------------------------------------------------------------------------

# Task Execution Role (pulls images, writes logs)
data "aws_iam_policy_document" "task_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.project_name}-${var.environment}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role (for application to access AWS services)
data "aws_iam_policy_document" "task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${var.project_name}-${var.environment}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

# Task permissions (S3, Secrets Manager, etc.)
data "aws_iam_policy_document" "task_permissions" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = ["arn:aws:s3:::*"]
  }

  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.project_name}/*"]
  }

  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters"
    ]
    resources = ["arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/*"]
  }

  statement {
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_permissions" {
  name   = "${var.project_name}-${var.environment}-task-permissions"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_permissions.json
}

# EventBridge Role (to run ECS tasks)
data "aws_iam_policy_document" "eventbridge_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge" {
  name               = "${var.project_name}-${var.environment}-eventbridge"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume.json
}

data "aws_iam_policy_document" "eventbridge_permissions" {
  statement {
    actions = ["ecs:RunTask"]
    resources = [
      "arn:aws:ecs:${var.aws_region}:*:task-definition/${var.project_name}-${var.environment}-*"
    ]
  }

  statement {
    actions   = ["iam:PassRole"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "eventbridge_permissions" {
  name   = "${var.project_name}-${var.environment}-eventbridge-permissions"
  role   = aws_iam_role.eventbridge.id
  policy = data.aws_iam_policy_document.eventbridge_permissions.json
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "scheduled_job" {
  family                   = "${var.project_name}-${var.environment}-scheduled-job"
  requires_compatibilities = [var.launch_type]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = "batch-job"
      image = var.container_image
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.scheduled_tasks.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "scheduled-job"
        }
      }

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "PROJECT_NAME"
          value = var.project_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]

      # Add secrets if needed
      # secrets = [
      #   {
      #     name      = "DATABASE_PASSWORD"
      #     valueFrom = "arn:aws:secretsmanager:region:account:secret:name"
      #   }
      # ]
    }
  ])

  # Fargate-specific configuration
  dynamic "runtime_platform" {
    for_each = var.launch_type == "FARGATE" ? [1] : []
    content {
      operating_system_family = "LINUX"
      cpu_architecture        = "X86_64"
    }
  }
}

# -----------------------------------------------------------------------------
# EventBridge Scheduled Rules
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "scheduled_job" {
  name                = "${var.project_name}-${var.environment}-scheduled-job"
  description         = "Trigger batch job on schedule"
  schedule_expression = var.schedule_expression
  is_enabled          = var.schedule_enabled
}

resource "aws_cloudwatch_event_target" "scheduled_job" {
  rule     = aws_cloudwatch_event_rule.scheduled_job.name
  arn      = data.aws_ecs_cluster.existing.arn
  role_arn = aws_iam_role.eventbridge.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.scheduled_job.arn
    launch_type         = var.launch_type
    platform_version    = var.launch_type == "FARGATE" ? "LATEST" : null

    network_configuration {
      subnets          = var.task_subnets
      security_groups  = var.task_security_groups
      assign_public_ip = var.assign_public_ip
    }
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms (Optional)
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  count = var.enable_alerts && var.alert_email != "" ? 1 : 0
  name  = "${var.project_name}-${var.environment}-scheduled-task-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.enable_alerts && var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alarm for task failures
resource "aws_cloudwatch_metric_alarm" "task_failures" {
  count = var.enable_alerts ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-task-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TasksFailed"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when ECS tasks fail"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = data.aws_ecs_cluster.existing.cluster_name
  }

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []
}

