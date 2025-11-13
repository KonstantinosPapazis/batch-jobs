# =============================================================================
# Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs where Fargate tasks run"
  value       = aws_subnet.private[*].id
}

output "compute_environment_arn" {
  description = "Batch compute environment ARN"
  value       = aws_batch_compute_environment.main.arn
}

output "job_queue_arn" {
  description = "Batch job queue ARN"
  value       = aws_batch_job_queue.main.arn
}

output "job_queue_name" {
  description = "Batch job queue name"
  value       = aws_batch_job_queue.main.name
}

output "job_definition_arn" {
  description = "Batch job definition ARN"
  value       = aws_batch_job_definition.main.arn
}

output "job_definition_name" {
  description = "Batch job definition name"
  value       = aws_batch_job_definition.main.name
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.batch_jobs.name
}

output "eventbridge_rule_name" {
  description = "EventBridge rule name for scheduled execution"
  value       = aws_cloudwatch_event_rule.daily_job.name
}

output "execution_role_arn" {
  description = "Task execution role ARN"
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "Task role ARN"
  value       = aws_iam_role.task.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts (if configured)"
  value       = var.enable_monitoring && var.alert_email != "" ? aws_sns_topic.alerts[0].arn : "Not configured"
}

# =============================================================================
# Useful Commands
# =============================================================================

output "manual_job_submission_command" {
  description = "Command to manually submit a job"
  value       = <<-EOT
    aws batch submit-job \
      --job-name "manual-test-$(date +%Y%m%d-%H%M%S)" \
      --job-queue ${aws_batch_job_queue.main.name} \
      --job-definition ${aws_batch_job_definition.main.name} \
      --region ${var.aws_region}
  EOT
}

output "view_logs_command" {
  description = "Command to view logs in real-time"
  value       = "aws logs tail ${aws_cloudwatch_log_group.batch_jobs.name} --follow --region ${var.aws_region}"
}

output "disable_schedule_command" {
  description = "Command to disable the scheduled execution"
  value       = "aws events disable-rule --name ${aws_cloudwatch_event_rule.daily_job.name} --region ${var.aws_region}"
}

output "enable_schedule_command" {
  description = "Command to enable the scheduled execution"
  value       = "aws events enable-rule --name ${aws_cloudwatch_event_rule.daily_job.name} --region ${var.aws_region}"
}

output "describe_job_command" {
  description = "Command to describe a specific job (replace JOB_ID)"
  value       = "aws batch describe-jobs --jobs JOB_ID --region ${var.aws_region}"
}

output "list_recent_jobs_command" {
  description = "Command to list recent jobs"
  value       = "aws batch list-jobs --job-queue ${aws_batch_job_queue.main.name} --job-status SUCCEEDED --region ${var.aws_region} --max-items 10"
}

# =============================================================================
# Deployment Summary
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed infrastructure"
  value       = <<-EOT
    ================================================================================
    AWS BATCH WITH FARGATE - PRODUCTION DEPLOYMENT
    ================================================================================
    
    PROJECT:        ${var.project_name}
    TEAM:           ${var.team_name}
    ENVIRONMENT:    ${var.environment}
    REGION:         ${var.aws_region}
    
    INFRASTRUCTURE:
    ├── VPC:                 ${aws_vpc.main.id}
    ├── Private Subnets:     ${length(aws_subnet.private)} subnets
    ├── VPC Endpoints:       ${var.create_vpc_endpoints ? "Enabled (saves ~$30/mo)" : "Disabled"}
    ├── Compute Environment: ${aws_batch_compute_environment.main.arn}
    ├── Job Queue:           ${aws_batch_job_queue.main.name}
    ├── Job Definition:      ${aws_batch_job_definition.main.name}
    └── Log Group:           ${aws_cloudwatch_log_group.batch_jobs.name}
    
    SCHEDULING:
    ├── Schedule:            ${var.schedule_expression}
    ├── Status:              ${var.schedule_enabled ? "ENABLED" : "DISABLED"}
    └── EventBridge Rule:    ${aws_cloudwatch_event_rule.daily_job.name}
    
    CONTAINER:
    ├── Image:               ${var.container_image}
    ├── Registry:            ${var.nexus_registry_url}
    ├── vCPU:                ${var.task_vcpu}
    ├── Memory:              ${var.task_memory} MB
    └── Timeout:             ${var.task_timeout_seconds} seconds
    
    MONITORING:
    ├── CloudWatch Logs:     ${aws_cloudwatch_log_group.batch_jobs.name}
    ├── Log Retention:       ${var.log_retention_days} days
    ├── Alarms:              ${var.enable_monitoring ? "Enabled" : "Disabled"}
    └── Alerts Email:        ${var.alert_email != "" ? var.alert_email : "Not configured"}
    
    NEXT STEPS:
    1. Verify Nexus credentials are stored in Secrets Manager
    2. Test job manually: See 'manual_job_submission_command' output
    3. Monitor logs: See 'view_logs_command' output
    4. Wait for 2 AM UTC for first scheduled run
    
    COST ESTIMATE (Monthly):
    - Fargate Compute:       ~$1.21 (30 hrs/mo × $0.04/hr)
    - VPC Endpoints:         ~$21.00 (3 endpoints)
    - CloudWatch Logs:       ~$2.50 (5 GB)
    - S3 Storage:            ~$2.30 (100 GB)
    - Total:                 ~$27/month
    
    ================================================================================
    
    To manually run a job now:
    aws batch submit-job --job-name "manual-test-$(date +%%Y%%m%%d-%%H%%M%%S)" --job-queue ${aws_batch_job_queue.main.name} --job-definition ${aws_batch_job_definition.main.name} --region ${var.aws_region}
    
    To view logs:
    aws logs tail ${aws_cloudwatch_log_group.batch_jobs.name} --follow --region ${var.aws_region}
    
    To disable schedule:
    aws events disable-rule --name ${aws_cloudwatch_event_rule.daily_job.name} --region ${var.aws_region}
    
    ================================================================================
  EOT
}

output "important_notes" {
  description = "Important notes and reminders"
  value       = <<-EOT
    ⚠️  IMPORTANT NOTES:
    
    1. NEXUS CONNECTIVITY:
       - Ensure your VPC can reach Nexus (${var.nexus_registry_url})
       - May need VPN or Direct Connect if Nexus is on-premise
       - Test connectivity from within the VPC
    
    2. SECRETS MANAGER:
       - Nexus credentials must be stored at: ${var.nexus_secret_arn}
       - Format: {"username": "...", "password": "...", "registry": "..."}
    
    3. SCHEDULE:
       - Jobs run at: ${var.schedule_expression}
       - This is UTC time (2 AM UTC = adjust for your timezone)
       - Current status: ${var.schedule_enabled ? "ENABLED" : "DISABLED"}
    
    4. MONITORING:
       - Check CloudWatch dashboard for metrics
       - Review alarms in CloudWatch Alarms console
       - ${var.alert_email != "" ? "Email alerts configured to: ${var.alert_email}" : "Configure alert_email for notifications"}
    
    5. S3 ACCESS:
       - Jobs can access buckets matching: ${join(", ", var.s3_bucket_arns)}
       - Update terraform.tfvars to add more buckets
    
    6. FIRST RUN:
       - Test manually before waiting for scheduled run
       - Check logs for any Nexus connection issues
       - Verify output is as expected
  EOT
}

