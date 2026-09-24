output "endpoint_address" {
  description = "Hostname the client connects to"
  value       = aws_elasticache_serverless_cache.this.endpoint[0].address
}

output "endpoint_port" {
  value = aws_elasticache_serverless_cache.this.endpoint[0].port
}

output "cache_name" {
  description = "Signing host for the IAM auth token"
  value       = aws_elasticache_serverless_cache.this.name
}

output "iam_user_name" {
  description = "Username presented alongside the IAM token"
  value       = aws_elasticache_user.iam.user_name
}

output "security_group_id" {
  value = aws_security_group.cache.id
}
