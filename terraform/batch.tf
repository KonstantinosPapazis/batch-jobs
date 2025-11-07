# -----------------------------------------------------------------------------
# AWS Batch Resources
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "batch_jobs" {
  name                 = "${local.name_prefix}-${var.ecr_repository_name}"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_image_scanning
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "batch_jobs" {
  count = var.ecr_lifecycle_policy ? 1 : 0

  repository = aws_ecr_repository.batch_jobs.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_lifecycle_count} images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_lifecycle_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "batch_jobs" {
  name              = "/aws/batch/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Batch Compute Environment
# -----------------------------------------------------------------------------

resource "aws_batch_compute_environment" "main" {
  compute_environment_name_prefix = "${local.name_prefix}-"
  type                            = "MANAGED"
  service_role                    = aws_iam_role.batch_service.arn

  compute_resources {
    type      = var.compute_environment_type
    max_vcpus = var.max_vcpus
    min_vcpus = var.min_vcpus

    security_group_ids = [aws_security_group.batch_compute.id]
    subnets            = aws_subnet.private[*].id

    # EC2-specific configuration
    dynamic "ec2_configuration" {
      for_each = var.compute_environment_type == "EC2" ? [1] : []
      content {
        image_type = "ECS_AL2"
      }
    }

    instance_role = var.compute_environment_type == "EC2" ? aws_iam_instance_profile.ecs_instance.arn : null
    instance_type = var.compute_environment_type == "EC2" ? var.instance_types : null

    # Spot configuration
    allocation_strategy = var.compute_type == "SPOT" ? "SPOT_CAPACITY_OPTIMIZED" : null
    bid_percentage      = var.compute_type == "SPOT" ? var.spot_bid_percentage : null
    spot_iam_fleet_role = var.compute_type == "SPOT" ? aws_iam_role.spot_fleet[0].arn : null

    # Optional EC2 key pair
    ec2_key_pair = var.ec2_key_pair != "" ? var.ec2_key_pair : null

    tags = merge(
      local.common_tags,
      {
        Name = "${local.name_prefix}-batch-compute"
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.batch_service
  ]
}

# -----------------------------------------------------------------------------
# Batch Job Queue
# -----------------------------------------------------------------------------

resource "aws_batch_job_queue" "main" {
  name     = "${local.name_prefix}-job-queue"
  state    = var.job_queue_state
  priority = var.job_queue_priority

  compute_environments = [
    aws_batch_compute_environment.main.arn
  ]

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Example Job Definition (you can customize or create more)
# -----------------------------------------------------------------------------

resource "aws_batch_job_definition" "example" {
  name = "${local.name_prefix}-example-job"
  type = "container"

  platform_capabilities = [
    var.compute_environment_type == "FARGATE" ? "FARGATE" : "EC2"
  ]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_jobs.repository_url}:latest"

    # Fargate requires specific resource requirements
    fargatePlatformConfiguration = var.compute_environment_type == "FARGATE" ? {
      platformVersion = "LATEST"
    } : null

    resourceRequirements = var.compute_environment_type == "FARGATE" ? [
      {
        type  = "VCPU"
        value = "0.25"
      },
      {
        type  = "MEMORY"
        value = "512"
      }
      ] : [
      {
        type  = "VCPU"
        value = "1"
      },
      {
        type  = "MEMORY"
        value = "2048"
      }
    ]

    jobRoleArn      = aws_iam_role.batch_job.arn
    executionRoleArn = aws_iam_role.batch_execution.arn

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

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "example-job"
      }
    }

    # Uncomment to use secrets from Secrets Manager
    # secrets = [
    #   {
    #     name      = "DATABASE_PASSWORD"
    #     valueFrom = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.project_name}/db-password"
    #   }
    # ]
  })

  retry_strategy {
    attempts = 3

    evaluate_on_exit {
      action       = "RETRY"
      on_status_reason = "Host EC2*"
    }

    evaluate_on_exit {
      action    = "EXIT"
      on_exit_code = "0"
    }
  }

  timeout {
    attempt_duration_seconds = 3600  # 1 hour timeout
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# EventBridge Scheduled Rule (Optional)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "scheduled_job" {
  count = var.enable_eventbridge_schedule ? 1 : 0

  name                = "${local.name_prefix}-scheduled-job"
  description         = "Trigger batch job on schedule"
  schedule_expression = var.schedule_expression
  state               = "ENABLED"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "batch_job" {
  count = var.enable_eventbridge_schedule ? 1 : 0

  rule     = aws_cloudwatch_event_rule.scheduled_job[0].name
  arn      = aws_batch_job_queue.main.arn
  role_arn = aws_iam_role.eventbridge[0].arn

  batch_target {
    job_definition = var.schedule_job_definition != "" ? var.schedule_job_definition : aws_batch_job_definition.example.name
    job_name       = "${local.name_prefix}-scheduled-job"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms (Optional)
# -----------------------------------------------------------------------------

# SNS Topic for Alarms
resource "aws_sns_topic" "batch_alerts" {
  count = var.enable_monitoring && var.alarm_email != "" ? 1 : 0

  name = "${local.name_prefix}-batch-alerts"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "batch_alerts_email" {
  count = var.enable_monitoring && var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.batch_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Alarm for failed jobs
resource "aws_cloudwatch_metric_alarm" "batch_job_failures" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-batch-job-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedJobs"
  namespace           = "AWS/Batch"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when batch jobs fail"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobQueue = aws_batch_job_queue.main.name
  }

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.batch_alerts[0].arn] : []

  tags = local.common_tags
}

