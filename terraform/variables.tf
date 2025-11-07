# -----------------------------------------------------------------------------
# Variables for AWS Batch Infrastructure
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
  description = "Enable NAT Gateway for private subnets (costs ~$32/month)"
  type        = bool
  default     = false  # Set to true if jobs need internet access
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for S3 and ECR (reduces NAT costs)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# AWS Batch Configuration
# -----------------------------------------------------------------------------

variable "compute_environment_type" {
  description = "Type of compute environment (EC2 or FARGATE)"
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "FARGATE"], var.compute_environment_type)
    error_message = "Compute environment type must be EC2 or FARGATE."
  }
}

variable "compute_type" {
  description = "Compute resource type (SPOT or ON_DEMAND)"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.compute_type)
    error_message = "Compute type must be SPOT or ON_DEMAND."
  }
}

variable "spot_bid_percentage" {
  description = "Maximum percentage of on-demand price to bid for spot instances"
  type        = number
  default     = 80

  validation {
    condition     = var.spot_bid_percentage > 0 && var.spot_bid_percentage <= 100
    error_message = "Spot bid percentage must be between 1 and 100."
  }
}

variable "min_vcpus" {
  description = "Minimum number of vCPUs in compute environment"
  type        = number
  default     = 0  # Scale to zero when idle
}

variable "max_vcpus" {
  description = "Maximum number of vCPUs in compute environment"
  type        = number
  default     = 256
}

variable "desired_vcpus" {
  description = "Desired number of vCPUs in compute environment"
  type        = number
  default     = 0  # Start with zero, scale as needed
}

variable "instance_types" {
  description = "List of instance types for compute environment"
  type        = list(string)
  default     = ["optimal"]  # Let AWS choose optimal instances
  # Or specify: ["t3.medium", "t3.large", "c5.large"]
}

variable "ec2_key_pair" {
  description = "EC2 key pair name for SSH access to compute instances (optional)"
  type        = string
  default     = ""
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

# -----------------------------------------------------------------------------
# ECR Configuration
# -----------------------------------------------------------------------------

variable "ecr_repository_name" {
  description = "Name for ECR repository"
  type        = string
  default     = "batch-jobs"
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
  default     = false  # Set to true to enable scheduled runs
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

