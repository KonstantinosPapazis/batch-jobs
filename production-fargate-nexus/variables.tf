# =============================================================================
# Core Configuration
# =============================================================================

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "batch-jobs"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "team_name" {
  description = "Team name (used for IAM role naming and resource tagging)"
  type        = string
  default     = "datascience"
}

# =============================================================================
# Nexus Registry Configuration
# =============================================================================

variable "nexus_registry_url" {
  description = "Nexus registry URL (e.g., nexus.company.com:5000)"
  type        = string
}

variable "nexus_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Nexus credentials"
  type        = string
}

variable "container_image" {
  description = "Full container image path from Nexus (e.g., nexus.company.com:5000/datascience/job:latest)"
  type        = string
}

# =============================================================================
# VPC Configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "create_vpc_endpoints" {
  description = "Create VPC endpoints for ECR, CloudWatch, S3 (recommended to avoid NAT Gateway costs)"
  type        = bool
  default     = true
}

# =============================================================================
# Fargate Task Configuration
# =============================================================================

variable "task_vcpu" {
  description = "vCPU for Fargate task (0.25, 0.5, 1, 2, 4)"
  type        = string
  default     = "0.25"

  validation {
    condition     = contains(["0.25", "0.5", "1", "2", "4"], var.task_vcpu)
    error_message = "vCPU must be 0.25, 0.5, 1, 2, or 4."
  }
}

variable "task_memory" {
  description = "Memory for Fargate task in MB (must match vCPU requirements)"
  type        = string
  default     = "512"
}

variable "task_timeout_seconds" {
  description = "Maximum time allowed for job execution (in seconds)"
  type        = number
  default     = 3600  # 1 hour
}

# =============================================================================
# Batch Configuration
# =============================================================================

variable "max_vcpus" {
  description = "Maximum vCPUs for Batch compute environment"
  type        = number
  default     = 256
}

variable "job_attempts" {
  description = "Number of retry attempts for failed jobs"
  type        = number
  default     = 2
}

# =============================================================================
# Scheduling
# =============================================================================

variable "schedule_expression" {
  description = "EventBridge schedule expression (cron or rate)"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC
}

variable "schedule_enabled" {
  description = "Enable the scheduled job execution"
  type        = bool
  default     = true
}

# =============================================================================
# Environment Variables for Container
# =============================================================================

variable "container_environment_vars" {
  description = "Environment variables to pass to the container"
  type        = map(string)
  default = {
    ENVIRONMENT = "production"
    LOG_LEVEL   = "INFO"
  }
}

# =============================================================================
# S3 Access Configuration
# =============================================================================

variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs the data science team can access"
  type        = list(string)
  default = [
    "arn:aws:s3:::datascience-*",
    "arn:aws:s3:::datascience-*/*"
  ]
}

# =============================================================================
# Monitoring & Alerting
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "enable_monitoring" {
  description = "Enable CloudWatch alarms and monitoring"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

# =============================================================================
# Tags
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

