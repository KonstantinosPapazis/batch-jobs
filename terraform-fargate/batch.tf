# -----------------------------------------------------------------------------
# AWS Batch Resources for Fargate
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
# Batch Compute Environment (FARGATE)
# -----------------------------------------------------------------------------

resource "aws_batch_compute_environment" "fargate" {
  compute_environment_name_prefix = "${local.name_prefix}-"
  type                            = "MANAGED"
  service_role                    = aws_iam_role.batch_service.arn

  compute_resources {
    type      = "FARGATE"
    max_vcpus = var.max_vcpus

    security_group_ids = [aws_security_group.fargate_tasks.id]
    subnets            = aws_subnet.private[*].id

    tags = merge(
      local.common_tags,
      {
        Name = "${local.name_prefix}-fargate-compute"
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

# Optional: Spot variant (not available for Fargate, so this is EC2 Spot as backup)
# Uncomment if you want a hybrid approach with EC2 Spot as fallback
# resource "aws_batch_compute_environment" "fargate_spot" {
#   compute_environment_name_prefix = "${local.name_prefix}-spot-"
#   type                            = "MANAGED"
#   service_role                    = aws_iam_role.batch_service.arn
#
#   compute_resources {
#     type      = "FARGATE_SPOT"
#     max_vcpus = var.max_vcpus
#
#     security_group_ids = [aws_security_group.fargate_tasks.id]
#     subnets            = aws_subnet.private[*].id
#   }
#
#   lifecycle {
#     create_before_destroy = true
#   }
#
#   depends_on = [
#     aws_iam_role_policy_attachment.batch_service
#   ]
# }

# -----------------------------------------------------------------------------
# Batch Job Queue
# -----------------------------------------------------------------------------

resource "aws_batch_job_queue" "main" {
  name     = "${local.name_prefix}-job-queue"
  state    = var.job_queue_state
  priority = var.job_queue_priority

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.fargate.arn
  }

  # Uncomment to add Fargate Spot as secondary compute environment
  # compute_environment_order {
  #   order               = 2
  #   compute_environment = aws_batch_compute_environment.fargate_spot.arn
  # }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Example Fargate Job Definitions
# -----------------------------------------------------------------------------

# Small Job (0.25 vCPU, 512 MB)
resource "aws_batch_job_definition" "small" {
  name = "${local.name_prefix}-small-job"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_jobs.repository_url}:latest"

    fargatePlatformConfiguration = {
      platformVersion = var.fargate_platform_version
    }

    resourceRequirements = [
      {
        type  = "VCPU"
        value = var.default_job_vcpu
      },
      {
        type  = "MEMORY"
        value = var.default_job_memory
      }
    ]

    jobRoleArn       = aws_iam_role.batch_job.arn
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
      },
      {
        name  = "COMPUTE_TYPE"
        value = "FARGATE"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "small-job"
      }
    }
  })

  retry_strategy {
    attempts = 3

    evaluate_on_exit {
      action           = "RETRY"
      on_status_reason = "Task failed to start"
    }

    evaluate_on_exit {
      action       = "EXIT"
      on_exit_code = "0"
    }
  }

  timeout {
    attempt_duration_seconds = 1800  # 30 minutes
  }

  tags = merge(
    local.common_tags,
    {
      JobSize = "Small"
    }
  )
}

# Medium Job (0.5 vCPU, 1024 MB)
resource "aws_batch_job_definition" "medium" {
  name = "${local.name_prefix}-medium-job"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_jobs.repository_url}:latest"

    fargatePlatformConfiguration = {
      platformVersion = var.fargate_platform_version
    }

    resourceRequirements = [
      {
        type  = "VCPU"
        value = "0.5"
      },
      {
        type  = "MEMORY"
        value = "1024"
      }
    ]

    jobRoleArn       = aws_iam_role.batch_job.arn
    executionRoleArn = aws_iam_role.batch_execution.arn

    environment = [
      {
        name  = "ENVIRONMENT"
        value = var.environment
      },
      {
        name  = "PROCESSING_MODE"
        value = "standard"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "medium-job"
      }
    }
  })

  retry_strategy {
    attempts = 3
  }

  timeout {
    attempt_duration_seconds = 3600  # 1 hour
  }

  tags = merge(
    local.common_tags,
    {
      JobSize = "Medium"
    }
  )
}

# Large Job (1 vCPU, 2048 MB)
resource "aws_batch_job_definition" "large" {
  name = "${local.name_prefix}-large-job"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_jobs.repository_url}:latest"

    fargatePlatformConfiguration = {
      platformVersion = var.fargate_platform_version
    }

    resourceRequirements = [
      {
        type  = "VCPU"
        value = "1"
      },
      {
        type  = "MEMORY"
        value = "2048"
      }
    ]

    jobRoleArn       = aws_iam_role.batch_job.arn
    executionRoleArn = aws_iam_role.batch_execution.arn

    environment = [
      {
        name  = "ENVIRONMENT"
        value = var.environment
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "large-job"
      }
    }
  })

  retry_strategy {
    attempts = 2
  }

  timeout {
    attempt_duration_seconds = 7200  # 2 hours
  }

  tags = merge(
    local.common_tags,
    {
      JobSize = "Large"
    }
  )
}

# -----------------------------------------------------------------------------
# EventBridge Scheduled Rule (Optional)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "scheduled_job" {
  count = var.enable_eventbridge_schedule ? 1 : 0

  name                = "${local.name_prefix}-scheduled-job"
  description         = "Trigger Fargate batch job on schedule"
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
    job_definition = var.schedule_job_definition != "" ? var.schedule_job_definition : aws_batch_job_definition.small.name
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
  alarm_description   = "Alert when Fargate batch jobs fail"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobQueue = aws_batch_job_queue.main.name
  }

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.batch_alerts[0].arn] : []

  tags = local.common_tags
}

