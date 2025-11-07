# -----------------------------------------------------------------------------
# Terraform Outputs for Fargate Deployment
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets (where Fargate tasks run)"
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
  description = "ARN of the Fargate Batch compute environment"
  value       = aws_batch_compute_environment.fargate.arn
}

output "batch_job_queue_arn" {
  description = "ARN of the Batch job queue"
  value       = aws_batch_job_queue.main.arn
}

output "batch_job_queue_name" {
  description = "Name of the Batch job queue"
  value       = aws_batch_job_queue.main.name
}

output "small_job_definition_arn" {
  description = "ARN of the small job definition (0.25 vCPU, 512 MB)"
  value       = aws_batch_job_definition.small.arn
}

output "small_job_definition_name" {
  description = "Name of the small job definition"
  value       = aws_batch_job_definition.small.name
}

output "medium_job_definition_arn" {
  description = "ARN of the medium job definition (0.5 vCPU, 1024 MB)"
  value       = aws_batch_job_definition.medium.arn
}

output "medium_job_definition_name" {
  description = "Name of the medium job definition"
  value       = aws_batch_job_definition.medium.name
}

output "large_job_definition_arn" {
  description = "ARN of the large job definition (1 vCPU, 2048 MB)"
  value       = aws_batch_job_definition.large.arn
}

output "large_job_definition_name" {
  description = "Name of the large job definition"
  value       = aws_batch_job_definition.large.name
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

output "docker_push_commands" {
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

output "submit_small_job_command" {
  description = "Command to submit a small test job (0.25 vCPU)"
  value       = <<-EOT
    aws batch submit-job \
      --job-name "small-test-$(date +%Y%m%d-%H%M%S)" \
      --job-queue ${aws_batch_job_queue.main.name} \
      --job-definition ${aws_batch_job_definition.small.name}
  EOT
}

output "submit_medium_job_command" {
  description = "Command to submit a medium test job (0.5 vCPU)"
  value       = <<-EOT
    aws batch submit-job \
      --job-name "medium-test-$(date +%Y%m%d-%H%M%S)" \
      --job-queue ${aws_batch_job_queue.main.name} \
      --job-definition ${aws_batch_job_definition.medium.name}
  EOT
}

output "fargate_resource_combinations" {
  description = "Valid Fargate vCPU and memory combinations"
  value       = <<-EOT
    Valid Fargate resource combinations:
    
    vCPU: 0.25 | Memory: 512, 1024, 2048 MB
    vCPU: 0.5  | Memory: 1024, 2048, 3072, 4096 MB
    vCPU: 1    | Memory: 2048, 3072, 4096, 5120, 6144, 7168, 8192 MB
    vCPU: 2    | Memory: 4096 to 16384 MB (1024 MB increments)
    vCPU: 4    | Memory: 8192 to 30720 MB (1024 MB increments)
  EOT
}

output "deployment_summary" {
  description = "Summary of deployed Fargate resources"
  value       = <<-EOT
    ===============================================================================
    AWS BATCH WITH FARGATE DEPLOYED SUCCESSFULLY
    ===============================================================================
    
    Region:                  ${var.aws_region}
    Environment:             ${var.environment}
    Project:                 ${var.project_name}
    Compute Type:            Fargate (Serverless)
    
    RESOURCES:
    - VPC:                   ${aws_vpc.main.id}
    - ECR Repository:        ${aws_ecr_repository.batch_jobs.repository_url}
    - Batch Job Queue:       ${aws_batch_job_queue.main.name}
    - Compute Environment:   ${aws_batch_compute_environment.fargate.arn}
    - Job Definitions:       
      * Small (0.25 vCPU):   ${aws_batch_job_definition.small.name}
      * Medium (0.5 vCPU):   ${aws_batch_job_definition.medium.name}
      * Large (1 vCPU):      ${aws_batch_job_definition.large.name}
    - CloudWatch Log Group:  ${aws_cloudwatch_log_group.batch_jobs.name}
    
    NETWORK:
    - VPC Endpoints:         ${var.enable_vpc_endpoints ? "Enabled (saves NAT costs)" : "Disabled"}
    - NAT Gateway:           ${var.enable_nat_gateway ? "Enabled" : "Disabled"}
    
    FARGATE BENEFITS:
    ✓ Fully serverless - no instance management
    ✓ Fast cold starts (30-60 seconds)
    ✓ Pay only for task execution time
    ✓ Automatic scaling
    
    COST ESTIMATE (2 jobs/day, 30 min each):
    - Compute:  ~$1.21/month (30 hrs × $0.04/hr)
    - Storage:  ~$3/month
    - Total:    ~$4-15/month
    
    NEXT STEPS:
    1. Build and push your Docker image to ECR
    2. Submit test jobs using the commands above
    3. Monitor jobs in CloudWatch Logs
    4. Enable EventBridge scheduling if needed
    
    For detailed instructions, see docs/MIGRATION_GUIDE.md
    ===============================================================================
  EOT
}

