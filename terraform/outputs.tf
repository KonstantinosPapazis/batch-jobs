# -----------------------------------------------------------------------------
# Terraform Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.batch_jobs.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.batch_jobs.arn
}

output "batch_compute_environment_arn" {
  description = "ARN of the Batch compute environment"
  value       = aws_batch_compute_environment.main.arn
}

output "batch_job_queue_arn" {
  description = "ARN of the Batch job queue"
  value       = aws_batch_job_queue.main.arn
}

output "batch_job_queue_name" {
  description = "Name of the Batch job queue"
  value       = aws_batch_job_queue.main.name
}

output "example_job_definition_arn" {
  description = "ARN of the example job definition"
  value       = aws_batch_job_definition.example.arn
}

output "example_job_definition_name" {
  description = "Name of the example job definition"
  value       = aws_batch_job_definition.example.name
}

output "batch_job_role_arn" {
  description = "ARN of the Batch job role"
  value       = aws_iam_role.batch_job.arn
}

output "batch_execution_role_arn" {
  description = "ARN of the Batch execution role"
  value       = aws_iam_role.batch_execution.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Batch jobs"
  value       = aws_cloudwatch_log_group.batch_jobs.name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge scheduled rule (if enabled)"
  value       = var.enable_eventbridge_schedule ? aws_cloudwatch_event_rule.scheduled_job[0].name : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts (if enabled)"
  value       = var.enable_monitoring && var.alarm_email != "" ? aws_sns_topic.batch_alerts[0].arn : null
}

# -----------------------------------------------------------------------------
# Quick Start Commands
# -----------------------------------------------------------------------------

output "docker_login_command" {
  description = "Command to authenticate Docker to ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.batch_jobs.repository_url}"
}

output "docker_push_command" {
  description = "Commands to build and push Docker image"
  value       = <<-EOT
    # Build your Docker image
    docker build -t ${var.project_name}:latest .
    
    # Tag for ECR
    docker tag ${var.project_name}:latest ${aws_ecr_repository.batch_jobs.repository_url}:latest
    
    # Push to ECR
    docker push ${aws_ecr_repository.batch_jobs.repository_url}:latest
  EOT
}

output "submit_job_command" {
  description = "Command to submit a test job"
  value       = <<-EOT
    aws batch submit-job \
      --job-name "test-job-$(date +%Y%m%d-%H%M%S)" \
      --job-queue ${aws_batch_job_queue.main.name} \
      --job-definition ${aws_batch_job_definition.example.name}
  EOT
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value       = <<-EOT
    ===============================================================================
    AWS BATCH INFRASTRUCTURE DEPLOYED SUCCESSFULLY
    ===============================================================================
    
    Region:                  ${var.aws_region}
    Environment:             ${var.environment}
    Project:                 ${var.project_name}
    
    RESOURCES:
    - VPC:                   ${aws_vpc.main.id}
    - ECR Repository:        ${aws_ecr_repository.batch_jobs.repository_url}
    - Batch Job Queue:       ${aws_batch_job_queue.main.name}
    - Compute Environment:   ${aws_batch_compute_environment.main.arn}
    - Example Job Def:       ${aws_batch_job_definition.example.name}
    - CloudWatch Log Group:  ${aws_cloudwatch_log_group.batch_jobs.name}
    
    NEXT STEPS:
    1. Build and push your Docker image to ECR
    2. Create job definitions for your workloads
    3. Submit test jobs to validate the setup
    4. Enable EventBridge scheduling if needed
    5. Configure monitoring and alerts
    
    For detailed instructions, see docs/MIGRATION_GUIDE.md
    ===============================================================================
  EOT
}

