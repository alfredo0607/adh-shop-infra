output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "Scopes the bucket policy to this distribution only"
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "Host the API builds signed URLs against"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "key_pair_id" {
  description = "Sent as Key-Pair-Id in every signed URL, so the API needs it"
  value       = aws_cloudfront_public_key.this.id
}
