# -----------------------------------------------------------------------------
# Example: Using IAM Roles Module for Multiple Teams
# -----------------------------------------------------------------------------
# This file demonstrates how to use the shared IAM roles module
# instead of creating individual roles per job
# -----------------------------------------------------------------------------

# Uncomment this entire file to use the modular approach!

/*

# Get current AWS account info
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Create Shared Roles for Data Engineering Team
# -----------------------------------------------------------------------------

module "data_engineering_roles" {
  source = "./modules/batch-iam-roles"

  project_name   = var.project_name
  team_name      = "data-engineering"
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Scope S3 access to team's buckets
  s3_resources = [
    "arn:aws:s3:::data-lake-${var.environment}/*",
    "arn:aws:s3:::data-lake-${var.environment}",
    "arn:aws:s3:::analytics-${var.environment}/*",
    "arn:aws:s3:::analytics-${var.environment}"
  ]

  # Enable services this team needs
  enable_secrets_manager = true
  enable_ssm_parameters  = true
  enable_dynamodb        = true
  
  dynamodb_table_arns = [
    "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/data-catalog-${var.environment}"
  ]

  tags = {
    Team = "DataEngineering"
  }
}

# -----------------------------------------------------------------------------
# Create Shared Roles for ML Team
# -----------------------------------------------------------------------------

module "ml_team_roles" {
  source = "./modules/batch-iam-roles"

  project_name   = var.project_name
  team_name      = "ml"
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  # ML team needs different S3 buckets
  s3_resources = [
    "arn:aws:s3:::ml-models-${var.environment}/*",
    "arn:aws:s3:::ml-training-data/*",
    "arn:aws:s3:::ml-inference-results/*"
  ]

  enable_secrets_manager = true
  enable_sqs             = true
  enable_sns             = true

  sqs_queue_arns = [
    "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:ml-inference-queue"
  ]

  sns_topic_arns = [
    "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:ml-notifications"
  ]

  tags = {
    Team = "MachineLearning"
  }
}

# -----------------------------------------------------------------------------
# Create Shared Roles for Analytics Team
# -----------------------------------------------------------------------------

module "analytics_team_roles" {
  source = "./modules/batch-iam-roles"

  project_name   = var.project_name
  team_name      = "analytics"
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  s3_resources = [
    "arn:aws:s3:::analytics-reports/*",
    "arn:aws:s3:::business-intelligence/*"
  ]

  enable_secrets_manager = true
  
  # Add custom policy for Athena/Glue access
  custom_job_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetDatabase",
          "glue:GetPartitions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Team = "Analytics"
  }
}

# -----------------------------------------------------------------------------
# Job Definitions Using Shared Roles
# -----------------------------------------------------------------------------

# Data Engineering Job 1
resource "aws_batch_job_definition" "data_pipeline_etl" {
  name = "${local.name_prefix}-data-pipeline-etl"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_jobs.repository_url}:latest"

    resourceRequirements = [
      { type = "VCPU", value = "0.5" },
      { type = "MEMORY", value = "1024" }
    ]

    # Use data engineering team's shared roles
    jobRoleArn       = module.data_engineering_roles.job_role_arn
    executionRoleArn = module.data_engineering_roles.execution_role_arn

    fargatePlatformConfiguration = {
      platformVersion = var.fargate_platform_version
    }

    environment = [
      { name = "JOB_TYPE", value = "etl" },
      { name = "TEAM", value = "data-engineering" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "data-etl"
      }
    }
  })

  retry_strategy {
    attempts = 3
  }

  timeout {
    attempt_duration_seconds = 3600
  }

  tags = {
    Team    = "DataEngineering"
    JobType = "ETL"
  }
}

# Data Engineering Job 2 (uses same roles!)
resource "aws_batch_job_definition" "data_aggregation" {
  name = "${local.name_prefix}-data-aggregation"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_jobs.repository_url}:latest"

    resourceRequirements = [
      { type = "VCPU", value = "1" },
      { type = "MEMORY", value = "2048" }
    ]

    # Same team, same roles!
    jobRoleArn       = module.data_engineering_roles.job_role_arn
    executionRoleArn = module.data_engineering_roles.execution_role_arn

    fargatePlatformConfiguration = {
      platformVersion = var.fargate_platform_version
    }

    environment = [
      { name = "JOB_TYPE", value = "aggregation" },
      { name = "TEAM", value = "data-engineering" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "data-agg"
      }
    }
  })

  retry_strategy {
    attempts = 2
  }

  timeout {
    attempt_duration_seconds = 7200
  }

  tags = {
    Team    = "DataEngineering"
    JobType = "Aggregation"
  }
}

# ML Team Job
resource "aws_batch_job_definition" "ml_training" {
  name = "${local.name_prefix}-ml-training"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_jobs.repository_url}:ml-latest"

    resourceRequirements = [
      { type = "VCPU", value = "2" },
      { type = "MEMORY", value = "4096" }
    ]

    # ML team's shared roles
    jobRoleArn       = module.ml_team_roles.job_role_arn
    executionRoleArn = module.ml_team_roles.execution_role_arn

    fargatePlatformConfiguration = {
      platformVersion = var.fargate_platform_version
    }

    environment = [
      { name = "JOB_TYPE", value = "training" },
      { name = "TEAM", value = "ml" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ml-training"
      }
    }
  })

  retry_strategy {
    attempts = 1  # Don't retry expensive training jobs
  }

  timeout {
    attempt_duration_seconds = 14400  # 4 hours
  }

  tags = {
    Team    = "MachineLearning"
    JobType = "Training"
  }
}

# Analytics Team Job
resource "aws_batch_job_definition" "analytics_report" {
  name = "${local.name_prefix}-analytics-report"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_jobs.repository_url}:latest"

    resourceRequirements = [
      { type = "VCPU", value = "0.25" },
      { type = "MEMORY", value = "512" }
    ]

    # Analytics team's shared roles (with Athena/Glue access)
    jobRoleArn       = module.analytics_team_roles.job_role_arn
    executionRoleArn = module.analytics_team_roles.execution_role_arn

    fargatePlatformConfiguration = {
      platformVersion = var.fargate_platform_version
    }

    environment = [
      { name = "JOB_TYPE", value = "report" },
      { name = "TEAM", value = "analytics" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "analytics-report"
      }
    }
  })

  retry_strategy {
    attempts = 3
  }

  timeout {
    attempt_duration_seconds = 1800
  }

  tags = {
    Team    = "Analytics"
    JobType = "Report"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "data_engineering_execution_role_arn" {
  description = "Data Engineering team execution role"
  value       = module.data_engineering_roles.execution_role_arn
}

output "data_engineering_job_role_arn" {
  description = "Data Engineering team job role"
  value       = module.data_engineering_roles.job_role_arn
}

output "ml_team_execution_role_arn" {
  description = "ML team execution role"
  value       = module.ml_team_roles.execution_role_arn
}

output "ml_team_job_role_arn" {
  description = "ML team job role"
  value       = module.ml_team_roles.job_role_arn
}

output "analytics_team_execution_role_arn" {
  description = "Analytics team execution role"
  value       = module.analytics_team_roles.execution_role_arn
}

output "analytics_team_job_role_arn" {
  description = "Analytics team job role"
  value       = module.analytics_team_roles.job_role_arn
}

output "iam_roles_summary" {
  description = "Summary of IAM roles created"
  value       = <<-EOT
    ============================================================================
    SHARED IAM ROLES CREATED
    ============================================================================
    
    Data Engineering Team:
      Execution Role: ${module.data_engineering_roles.execution_role_name}
      Job Role:       ${module.data_engineering_roles.job_role_name}
      Used by: data-pipeline-etl, data-aggregation
    
    ML Team:
      Execution Role: ${module.ml_team_roles.execution_role_name}
      Job Role:       ${module.ml_team_roles.job_role_name}
      Used by: ml-training
    
    Analytics Team:
      Execution Role: ${module.analytics_team_roles.execution_role_name}
      Job Role:       ${module.analytics_team_roles.job_role_name}
      Used by: analytics-report
    
    TOTAL: 6 roles (3 teams × 2 roles) instead of 8 roles (4 jobs × 2 roles)
    ============================================================================
  EOT
}

*/

# -----------------------------------------------------------------------------
# To use this approach:
# 1. Uncomment this entire file
# 2. Comment out the individual IAM roles in iam.tf
# 3. Run: terraform plan
# 4. Review changes
# 5. Run: terraform apply
# -----------------------------------------------------------------------------

