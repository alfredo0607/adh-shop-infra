output "distribution_id" {
  description = "Needed to invalidate the cache after a front-end deployment"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "Scopes the bucket policy to this distribution only"
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}
