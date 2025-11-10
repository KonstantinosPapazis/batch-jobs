# -----------------------------------------------------------------------------
# Outputs for Batch IAM Roles Module
# -----------------------------------------------------------------------------

output "execution_role_arn" {
  description = "ARN of the batch execution role (use for job definitions)"
  value       = aws_iam_role.execution.arn
}

output "execution_role_name" {
  description = "Name of the batch execution role"
  value       = aws_iam_role.execution.name
}

output "job_role_arn" {
  description = "ARN of the batch job role (use for job definitions)"
  value       = aws_iam_role.job.arn
}

output "job_role_name" {
  description = "Name of the batch job role"
  value       = aws_iam_role.job.name
}

output "team_prefix" {
  description = "The team prefix used for naming"
  value       = local.team_prefix
}

