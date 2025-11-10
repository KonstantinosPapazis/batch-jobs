# -----------------------------------------------------------------------------
# Variables for Batch IAM Roles Module
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "team_name" {
  description = "Team name (e.g., 'data-engineering', 'ml', 'analytics')"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

# -----------------------------------------------------------------------------
# Feature Flags
# -----------------------------------------------------------------------------

variable "enable_secrets_manager" {
  description = "Enable Secrets Manager access for this team"
  type        = bool
  default     = true
}

variable "enable_ssm_parameters" {
  description = "Enable SSM Parameter Store access for this team"
  type        = bool
  default     = true
}

variable "enable_dynamodb" {
  description = "Enable DynamoDB access for this team"
  type        = bool
  default     = false
}

variable "enable_sqs" {
  description = "Enable SQS access for this team"
  type        = bool
  default     = false
}

variable "enable_sns" {
  description = "Enable SNS access for this team"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Resource-specific permissions
# -----------------------------------------------------------------------------

variable "s3_resources" {
  description = "List of S3 bucket ARNs and prefixes the team can access"
  type        = list(string)
  default = [
    "arn:aws:s3:::*"  # Default: all buckets (should be scoped down!)
  ]
}

variable "dynamodb_table_arns" {
  description = "List of DynamoDB table ARNs the team can access"
  type        = list(string)
  default     = []
}

variable "sqs_queue_arns" {
  description = "List of SQS queue ARNs the team can access"
  type        = list(string)
  default     = []
}

variable "sns_topic_arns" {
  description = "List of SNS topic ARNs the team can access"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Custom policies
# -----------------------------------------------------------------------------

variable "custom_job_policy_json" {
  description = "Custom IAM policy JSON for additional job permissions"
  type        = string
  default     = ""
}

variable "managed_policy_arns" {
  description = "List of managed policy ARNs to attach to the job role"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to IAM roles"
  type        = map(string)
  default     = {}
}

