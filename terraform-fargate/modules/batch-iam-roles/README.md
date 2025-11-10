# AWS Batch IAM Roles Module

Reusable Terraform module for creating shared IAM roles for AWS Batch teams. This module creates **one set of roles per team** that can be shared across multiple batch job definitions.

## 🎯 Why Use This Module?

### Problem: Too Many IAM Roles
```
❌ Without Module (One role per job):
- data-pipeline-job-1-execution-role
- data-pipeline-job-1-job-role
- data-pipeline-job-2-execution-role
- data-pipeline-job-2-job-role
- ml-training-job-execution-role
- ml-training-job-job-role
... 100+ roles to manage!
```

### Solution: Shared Team Roles
```
✅ With Module (One role per team):
- data-engineering-prod-batch-execution-role (shared by all data jobs)
- data-engineering-prod-batch-job-role (shared by all data jobs)
- ml-team-prod-batch-execution-role (shared by all ML jobs)
- ml-team-prod-batch-job-role (shared by all ML jobs)
... Only 2 roles per team!
```

## 🏗️ What This Module Creates

For each team, it creates:

1. **Execution Role** - Used by AWS to:
   - Pull Docker images from ECR
   - Write logs to CloudWatch
   - Access secrets during container startup

2. **Job Role** - Used by your application to:
   - Access S3 buckets
   - Read/write to DynamoDB
   - Publish to SNS/SQS
   - Put CloudWatch metrics

## 📚 Usage Examples

### Basic Example: Single Team

```hcl
# Create roles for data engineering team
module "data_engineering_roles" {
  source = "./modules/batch-iam-roles"

  project_name   = "batch-jobs"
  team_name      = "data-engineering"
  environment    = "prod"
  aws_region     = "us-east-1"
  aws_account_id = data.aws_caller_identity.current.account_id

  # Scope S3 access to team's buckets
  s3_resources = [
    "arn:aws:s3:::data-lake-prod/*",
    "arn:aws:s3:::data-lake-prod",
    "arn:aws:s3:::analytics-temp/*"
  ]
}

# Use these roles in ALL data engineering job definitions
resource "aws_batch_job_definition" "data_pipeline_1" {
  name = "data-pipeline-1"
  type = "container"
  
  platform_capabilities = ["FARGATE"]
  
  container_properties = jsonencode({
    executionRoleArn = module.data_engineering_roles.execution_role_arn
    jobRoleArn       = module.data_engineering_roles.job_role_arn
    # ... rest of config
  })
}

resource "aws_batch_job_definition" "data_pipeline_2" {
  name = "data-pipeline-2"
  type = "container"
  
  platform_capabilities = ["FARGATE"]
  
  container_properties = jsonencode({
    executionRoleArn = module.data_engineering_roles.execution_role_arn
    jobRoleArn       = module.data_engineering_roles.job_role_arn
    # ... rest of config
  })
}
```

### Multi-Team Example

```hcl
# Data Engineering Team
module "data_engineering_roles" {
  source = "./modules/batch-iam-roles"

  project_name   = "batch-jobs"
  team_name      = "data-engineering"
  environment    = "prod"
  aws_region     = "us-east-1"
  aws_account_id = data.aws_caller_identity.current.account_id

  s3_resources = [
    "arn:aws:s3:::data-lake-prod/*",
    "arn:aws:s3:::data-lake-prod"
  ]
  
  enable_dynamodb = true
  dynamodb_table_arns = [
    "arn:aws:dynamodb:us-east-1:123456789012:table/data-catalog"
  ]
}

# ML Team
module "ml_team_roles" {
  source = "./modules/batch-iam-roles"

  project_name   = "batch-jobs"
  team_name      = "ml"
  environment    = "prod"
  aws_region     = "us-east-1"
  aws_account_id = data.aws_caller_identity.current.account_id

  s3_resources = [
    "arn:aws:s3:::ml-models-prod/*",
    "arn:aws:s3:::ml-training-data/*"
  ]
  
  enable_sqs = true
  sqs_queue_arns = [
    "arn:aws:sqs:us-east-1:123456789012:ml-inference-queue"
  ]
}

# Analytics Team
module "analytics_team_roles" {
  source = "./modules/batch-iam-roles"

  project_name   = "batch-jobs"
  team_name      = "analytics"
  environment    = "prod"
  aws_region     = "us-east-1"
  aws_account_id = data.aws_caller_identity.current.account_id

  s3_resources = [
    "arn:aws:s3:::analytics-reports/*"
  ]
  
  enable_sns = true
  sns_topic_arns = [
    "arn:aws:sns:us-east-1:123456789012:report-notifications"
  ]
}
```

### Advanced: Custom Policies

```hcl
module "data_engineering_roles" {
  source = "./modules/batch-iam-roles"

  project_name   = "batch-jobs"
  team_name      = "data-engineering"
  environment    = "prod"
  aws_region     = "us-east-1"
  aws_account_id = data.aws_caller_identity.current.account_id

  # Standard S3 access
  s3_resources = ["arn:aws:s3:::data-lake-prod/*"]

  # Add custom policy for special needs
  custom_job_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetDatabase"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution"
        ]
        Resource = "*"
      }
    ]
  })

  # Or attach managed policies
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
  ]
}
```

## 🔐 Security Best Practices

### 1. Scope S3 Access by Team

```hcl
# ❌ Bad: Too broad
s3_resources = ["arn:aws:s3:::*"]

# ✅ Good: Scoped to team
s3_resources = [
  "arn:aws:s3:::team-data-bucket/*",
  "arn:aws:s3:::team-data-bucket",
  "arn:aws:s3:::shared-bucket/team-prefix/*"
]
```

### 2. Use Consistent Naming Convention

```hcl
team_name = "data-engineering"  # Results in: batch-jobs-data-engineering-prod-*
team_name = "ml"                # Results in: batch-jobs-ml-prod-*
team_name = "analytics"         # Results in: batch-jobs-analytics-prod-*
```

### 3. Separate Environments

```hcl
# Development
module "data_eng_dev" {
  source      = "./modules/batch-iam-roles"
  team_name   = "data-engineering"
  environment = "dev"
  # ... less restrictive permissions
}

# Production
module "data_eng_prod" {
  source      = "./modules/batch-iam-roles"
  team_name   = "data-engineering"
  environment = "prod"
  # ... more restrictive permissions
}
```

### 4. Organize Secrets by Team

```
Secrets Manager structure:
/batch-jobs/data-engineering/db-password
/batch-jobs/data-engineering/api-key
/batch-jobs/ml/model-api-key
/batch-jobs/analytics/warehouse-creds

This module automatically scopes access:
- data-engineering team can only access /batch-jobs/data-engineering/*
- ml team can only access /batch-jobs/ml/*
```

## 📊 Benefits vs One Role Per Job

| Aspect | One Role Per Team (Module) | One Role Per Job |
|--------|---------------------------|------------------|
| **# of Roles** | 2 × teams (scalable) | 2 × jobs (explodes) |
| **Management** | ✅ Simple | ❌ Complex |
| **Consistency** | ✅ Consistent across team | ⚠️ Can drift |
| **Auditing** | ✅ Easy (team-level) | ⚠️ Hard (job-level) |
| **Updates** | ✅ Update once, affects all | ❌ Update each role |
| **Security** | ✅ Good (team isolation) | ✅✅ Best (job isolation) |

## 🎯 When to Use Module vs Individual Roles

### Use This Module (Shared Roles) When:
- ✅ **Most cases** (recommended for 90% of scenarios)
- ✅ Multiple jobs with **similar permission needs**
- ✅ Team-based access control is sufficient
- ✅ Want **easy management**
- ✅ 10+ jobs per team

### Use Individual Roles When:
- ⚠️ **Strict compliance** requirements (SOC2, HIPAA, PCI-DSS)
- ⚠️ Each job needs **very different** permissions
- ⚠️ **Maximum isolation** required
- ⚠️ Few jobs (< 5 total)

## 📝 Input Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `project_name` | string | - | Project name |
| `team_name` | string | - | Team name (e.g., "data-engineering") |
| `environment` | string | - | Environment (dev, staging, prod) |
| `aws_region` | string | - | AWS region |
| `aws_account_id` | string | - | AWS account ID |
| `s3_resources` | list(string) | `["arn:aws:s3:::*"]` | S3 resources team can access |
| `enable_secrets_manager` | bool | `true` | Enable Secrets Manager access |
| `enable_ssm_parameters` | bool | `true` | Enable SSM Parameter Store |
| `enable_dynamodb` | bool | `false` | Enable DynamoDB access |
| `enable_sqs` | bool | `false` | Enable SQS access |
| `enable_sns` | bool | `false` | Enable SNS access |
| `dynamodb_table_arns` | list(string) | `[]` | DynamoDB tables |
| `sqs_queue_arns` | list(string) | `[]` | SQS queues |
| `sns_topic_arns` | list(string) | `[]` | SNS topics |
| `custom_job_policy_json` | string | `""` | Custom IAM policy JSON |
| `managed_policy_arns` | list(string) | `[]` | Managed policies to attach |

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `execution_role_arn` | ARN of execution role (use in job definitions) |
| `execution_role_name` | Name of execution role |
| `job_role_arn` | ARN of job role (use in job definitions) |
| `job_role_name` | Name of job role |
| `team_prefix` | The team prefix used for naming |

## 🔄 Migration from Individual Roles

If you already have individual roles per job:

```hcl
# Before (one role per job)
resource "aws_iam_role" "job1_execution" { ... }
resource "aws_iam_role" "job1_job" { ... }
resource "aws_iam_role" "job2_execution" { ... }
resource "aws_iam_role" "job2_job" { ... }

# After (one role per team)
module "team_roles" {
  source = "./modules/batch-iam-roles"
  # ... config
}

# Update all job definitions to use module outputs
executionRoleArn = module.team_roles.execution_role_arn
jobRoleArn       = module.team_roles.job_role_arn

# Then delete old individual roles
# terraform state rm aws_iam_role.job1_execution
# terraform state rm aws_iam_role.job1_job
# ...
```

## 📚 Examples Directory

See `examples/` for complete working examples:
- `examples/single-team/` - Simple single team setup
- `examples/multi-team/` - Multiple teams with different permissions
- `examples/advanced/` - Custom policies and managed policies

## 🤝 Contributing

To add new features or fix bugs in this module:
1. Update `main.tf` with new functionality
2. Add variables to `variables.tf`
3. Update outputs in `outputs.tf`
4. Update this README with examples

---

**Recommended**: Use this module! It simplifies management while maintaining good security.

