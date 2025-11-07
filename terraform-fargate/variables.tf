# -----------------------------------------------------------------------------
# Variables for AWS Batch with Fargate
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "batch-jobs"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets (required for Fargate to pull images if not using VPC endpoints)"
  type        = bool
  default     = false  # VPC endpoints recommended
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for S3 and ECR (strongly recommended for Fargate to avoid NAT costs)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# AWS Batch Fargate Configuration
# -----------------------------------------------------------------------------

variable "max_vcpus" {
  description = "Maximum vCPUs in Fargate compute environment"
  type        = number
  default     = 256
}

variable "fargate_platform_version" {
  description = "Fargate platform version"
  type        = string
  default     = "LATEST"
}

# -----------------------------------------------------------------------------
# Job Configuration
# -----------------------------------------------------------------------------

variable "job_queue_priority" {
  description = "Priority for the default job queue"
  type        = number
  default     = 1
}

variable "job_queue_state" {
  description = "State of job queue (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.job_queue_state)
    error_message = "Job queue state must be ENABLED or DISABLED."
  }
}

# Default Fargate job resources
variable "default_job_vcpu" {
  description = "Default vCPU for jobs (Fargate values: 0.25, 0.5, 1, 2, 4)"
  type        = string
  default     = "0.25"

  validation {
    condition     = contains(["0.25", "0.5", "1", "2", "4"], var.default_job_vcpu)
    error_message = "vCPU must be one of: 0.25, 0.5, 1, 2, 4"
  }
}

variable "default_job_memory" {
  description = "Default memory in MB for jobs (must match vCPU requirements)"
  type        = string
  default     = "512"
}

# -----------------------------------------------------------------------------
# ECR Configuration
# -----------------------------------------------------------------------------

variable "ecr_repository_name" {
  description = "Name for ECR repository"
  type        = string
  default     = "batch-jobs-fargate"
}

variable "ecr_image_scanning" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "Image tag mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "ecr_lifecycle_policy" {
  description = "Enable lifecycle policy to clean up old images"
  type        = bool
  default     = true
}

variable "ecr_lifecycle_count" {
  description = "Number of images to retain in ECR"
  type        = number
  default     = 10
}

# -----------------------------------------------------------------------------
# CloudWatch Configuration
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention value."
  }
}

# -----------------------------------------------------------------------------
# EventBridge Scheduling (Optional)
# -----------------------------------------------------------------------------

variable "enable_eventbridge_schedule" {
  description = "Enable EventBridge rule for scheduled job execution"
  type        = bool
  default     = false
}

variable "schedule_expression" {
  description = "Cron or rate expression for EventBridge schedule"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC
}

variable "schedule_job_definition" {
  description = "Job definition name to use for scheduled runs"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Monitoring and Alerting
# -----------------------------------------------------------------------------

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

