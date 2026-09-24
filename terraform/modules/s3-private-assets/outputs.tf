output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "CloudFront origin domain. The regional form avoids a redirect on first request"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
