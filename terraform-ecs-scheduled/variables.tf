# -----------------------------------------------------------------------------
# Variables for ECS Scheduled Tasks (Using Existing Cluster)
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "batch-jobs"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Existing Resources
# -----------------------------------------------------------------------------

variable "existing_cluster_name" {
  description = "Name of your existing ECS cluster"
  type        = string
}

variable "existing_vpc_id" {
  description = "ID of existing VPC (optional, for data source lookup)"
  type        = string
  default     = ""
}

variable "subnet_tags" {
  description = "Tags to filter subnets (if using VPC data source)"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Task Configuration
# -----------------------------------------------------------------------------

variable "launch_type" {
  description = "Launch type for ECS tasks (FARGATE or EC2)"
  type        = string
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "EC2"], var.launch_type)
    error_message = "Launch type must be FARGATE or EC2"
  }
}

variable "task_cpu" {
  description = "CPU units for task (Fargate: 256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Memory for task in MB (must match CPU for Fargate)"
  type        = string
  default     = "512"
}

variable "container_image" {
  description = "Container image to use (ECR URI or Docker Hub)"
  type        = string
}

variable "task_subnets" {
  description = "List of subnet IDs where tasks will run"
  type        = list(string)
}

variable "task_security_groups" {
  description = "List of security group IDs for tasks"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks (needed if pulling from public registries)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Scheduling
# -----------------------------------------------------------------------------

variable "schedule_expression" {
  description = "EventBridge schedule expression (cron or rate)"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC
}

variable "schedule_enabled" {
  description = "Enable the scheduled rule"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------

variable "create_ecr_repository" {
  description = "Create ECR repository for container images"
  type        = bool
  default     = false  # Set to true if you don't have one
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

variable "enable_alerts" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

