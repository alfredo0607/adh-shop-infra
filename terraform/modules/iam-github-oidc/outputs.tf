output "role_arn" {
  description = "Set as AWS_DEPLOY_ROLE in the workflow"
  value       = aws_iam_role.this.arn
}
