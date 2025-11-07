# -----------------------------------------------------------------------------
# Outputs for ECS Scheduled Tasks
# -----------------------------------------------------------------------------

output "ecs_cluster_name" {
  description = "Name of the ECS cluster being used"
  value       = data.aws_ecs_cluster.existing.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = data.aws_ecs_cluster.existing.arn
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.scheduled_job.arn
}

output "task_definition_family" {
  description = "Family of the task definition"
  value       = aws_ecs_task_definition.scheduled_job.family
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.scheduled_job.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.scheduled_job.arn
}

output "task_execution_role_arn" {
  description = "ARN of task execution role"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ARN of task role"
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "Name of CloudWatch log group"
  value       = aws_cloudwatch_log_group.scheduled_tasks.name
}

output "ecr_repository_url" {
  description = "URL of ECR repository (if created)"
  value       = var.create_ecr_repository ? aws_ecr_repository.batch_job[0].repository_url : "Not created - using existing"
}

output "manual_run_command" {
  description = "Command to manually run the task"
  value       = <<-EOT
    aws ecs run-task \
      --cluster ${data.aws_ecs_cluster.existing.cluster_name} \
      --task-definition ${aws_ecs_task_definition.scheduled_job.family} \
      --launch-type ${var.launch_type} \
      --network-configuration "awsvpcConfiguration={subnets=[${join(",", var.task_subnets)}],securityGroups=[${join(",", var.task_security_groups)}],assignPublicIp=${var.assign_public_ip ? "ENABLED" : "DISABLED"}}"
  EOT
}

output "disable_schedule_command" {
  description = "Command to disable the schedule"
  value       = "aws events disable-rule --name ${aws_cloudwatch_event_rule.scheduled_job.name}"
}

output "enable_schedule_command" {
  description = "Command to enable the schedule"
  value       = "aws events enable-rule --name ${aws_cloudwatch_event_rule.scheduled_job.name}"
}

output "view_logs_command" {
  description = "Command to view logs"
  value       = "aws logs tail ${aws_cloudwatch_log_group.scheduled_tasks.name} --follow"
}

output "summary" {
  description = "Deployment summary"
  value       = <<-EOT
    ===============================================================================
    ECS SCHEDULED TASKS DEPLOYED
    ===============================================================================
    
    Cluster:               ${data.aws_ecs_cluster.existing.cluster_name}
    Task Definition:       ${aws_ecs_task_definition.scheduled_job.family}
    Schedule:              ${var.schedule_expression}
    Schedule Enabled:      ${var.schedule_enabled}
    Launch Type:           ${var.launch_type}
    CPU:                   ${var.task_cpu}
    Memory:                ${var.task_memory}
    
    USING YOUR EXISTING ECS CLUSTER!
    
    To manually run:
    ${chomp(self.manual_run_command)}
    
    To view logs:
    ${chomp(self.view_logs_command)}
    
    To disable schedule:
    ${chomp(self.disable_schedule_command)}
    ===============================================================================
  EOT
}

