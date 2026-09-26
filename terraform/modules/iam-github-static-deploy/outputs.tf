output "role_arn" {
  description = "Set as AWS_DEPLOY_ROLE_ARN in the storefront's production environment"
  value       = aws_iam_role.this.arn
}
