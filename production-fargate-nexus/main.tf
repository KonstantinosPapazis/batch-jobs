# =============================================================================
# Production AWS Batch with Fargate - Data Science Team
# Using External Nexus Registry
# =============================================================================

# Data Sources
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.team_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition

  common_tags = merge(
    {
      Name        = local.name_prefix
      Team        = var.team_name
      Project     = var.project_name
      Environment = var.environment
    },
    var.additional_tags
  )
}

# =============================================================================
# VPC and Networking
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-vpc" }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-igw" }
  )
}

# Public Subnets (for VPC endpoints and potential NAT if needed)
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
      Type = "Public"
    }
  )
}

# Private Subnets (Fargate tasks run here)
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
      Type = "Private"
    }
  )
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-public-rt" }
  )
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-private-rt" }
  )
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# Security Groups
# =============================================================================

resource "aws_security_group" "fargate_tasks" {
  name_prefix = "${local.name_prefix}-fargate-tasks-"
  description = "Security group for Fargate Batch tasks"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-fargate-tasks-sg" }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.create_vpc_endpoints ? 1 : 0

  name_prefix = "${local.name_prefix}-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow HTTPS from Fargate tasks"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.fargate_tasks.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-vpc-endpoints-sg" }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# VPC Endpoints (Saves NAT Gateway costs ~$32/month)
# =============================================================================

# S3 Gateway Endpoint (Free)
resource "aws_vpc_endpoint" "s3" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-s3-endpoint" }
  )
}

# ECR API Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-ecr-api-endpoint" }
  )
}

# ECR Docker Endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-ecr-dkr-endpoint" }
  )
}

# CloudWatch Logs Endpoint
resource "aws_vpc_endpoint" "logs" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-logs-endpoint" }
  )
}

# =============================================================================
# IAM Roles
# =============================================================================

# Batch Service Role
data "aws_iam_policy_document" "batch_service_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "batch_service" {
  name               = "${local.name_prefix}-batch-service-role"
  assume_role_policy = data.aws_iam_policy_document.batch_service_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "batch_service" {
  role       = aws_iam_role.batch_service.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# Task Execution Role (for pulling images and writing logs)
data "aws_iam_policy_document" "execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.execution_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "execution_standard" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional execution permissions (Nexus credentials, logs)
data "aws_iam_policy_document" "execution_additional" {
  # Access to Nexus credentials in Secrets Manager
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      var.nexus_secret_arn,
      "${var.nexus_secret_arn}*"  # Handle versioning
    ]
  }

  # CloudWatch Logs
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
}

resource "aws_iam_role_policy" "execution_additional" {
  name   = "${local.name_prefix}-execution-additional"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_additional.json
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
  name               = "${local.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
  tags               = local.common_tags
}

# Task permissions (S3, CloudWatch, Secrets Manager)
data "aws_iam_policy_document" "task_permissions" {
  # S3 access (scoped to data science buckets)
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = var.s3_bucket_arns
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

  # CloudWatch Logs
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

  # Secrets Manager (for application secrets, not Nexus)
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.project_name}/${var.team_name}/*"
    ]
  }
}

resource "aws_iam_role_policy" "task_permissions" {
  name   = "${local.name_prefix}-task-permissions"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_permissions.json
}

# EventBridge Role (to submit batch jobs)
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
  name               = "${local.name_prefix}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "eventbridge_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "batch:SubmitJob"
    ]
    resources = [
      aws_batch_job_queue.main.arn,
      aws_batch_job_definition.main.arn
    ]
  }
}

resource "aws_iam_role_policy" "eventbridge_permissions" {
  name   = "${local.name_prefix}-eventbridge-permissions"
  role   = aws_iam_role.eventbridge.id
  policy = data.aws_iam_policy_document.eventbridge_permissions.json
}

# =============================================================================
# CloudWatch Logs
# =============================================================================

resource "aws_cloudwatch_log_group" "batch_jobs" {
  name              = "/aws/batch/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# =============================================================================
# AWS Batch Resources
# =============================================================================

# Compute Environment (Fargate)
resource "aws_batch_compute_environment" "main" {
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
      { Name = "${local.name_prefix}-fargate-compute" }
    )
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.batch_service
  ]
}

# Job Queue
resource "aws_batch_job_queue" "main" {
  name     = "${local.name_prefix}-job-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.main.arn
  }

  tags = local.common_tags
}

# Job Definition
resource "aws_batch_job_definition" "main" {
  name = "${local.name_prefix}-daily-job"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = var.container_image

    fargatePlatformConfiguration = {
      platformVersion = "LATEST"
    }

    resourceRequirements = [
      {
        type  = "VCPU"
        value = var.task_vcpu
      },
      {
        type  = "MEMORY"
        value = var.task_memory
      }
    ]

    jobRoleArn       = aws_iam_role.task.arn
    executionRoleArn = aws_iam_role.execution.arn

    # Environment variables
    environment = [
      for key, value in var.container_environment_vars : {
        name  = key
        value = value
      }
    ]

    # Nexus credentials from Secrets Manager
    # The execution role can access this secret
    repositoryCredentials = {
      credentialsParameter = var.nexus_secret_arn
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "daily-job"
      }
    }
  })

  retry_strategy {
    attempts = var.job_attempts

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
    attempt_duration_seconds = var.task_timeout_seconds
  }

  tags = merge(
    local.common_tags,
    {
      Schedule = "Daily-2AM"
    }
  )
}

# =============================================================================
# EventBridge Scheduling (Daily at 2 AM)
# =============================================================================

resource "aws_cloudwatch_event_rule" "daily_job" {
  name                = "${local.name_prefix}-daily-job"
  description         = "Trigger data science batch job daily at 2 AM UTC"
  schedule_expression = var.schedule_expression
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "batch_job" {
  rule     = aws_cloudwatch_event_rule.daily_job.name
  arn      = aws_batch_job_queue.main.arn
  role_arn = aws_iam_role.eventbridge.arn

  batch_target {
    job_definition = aws_batch_job_definition.main.name
    job_name       = "${local.name_prefix}-scheduled-job"
  }
}

# =============================================================================
# Monitoring & Alerts
# =============================================================================

# SNS Topic for Alarms
resource "aws_sns_topic" "alerts" {
  count = var.enable_monitoring && var.alert_email != "" ? 1 : 0

  name = "${local.name_prefix}-batch-alerts"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.enable_monitoring && var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alarm for Failed Jobs
resource "aws_cloudwatch_metric_alarm" "job_failures" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-job-failures"
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

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = local.common_tags
}

# Alarm for Job Queue Depth (jobs stuck in queue)
resource "aws_cloudwatch_metric_alarm" "queue_depth" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningJobs"
  namespace           = "AWS/Batch"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "Alert when too many jobs are stuck in queue"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobQueue = aws_batch_job_queue.main.name
  }

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = local.common_tags
}

