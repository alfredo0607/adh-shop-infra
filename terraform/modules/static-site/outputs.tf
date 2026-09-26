output "bucket_name" {
  description = "Where the deployment uploads the build"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "distribution_id" {
  description = "What the deployment invalidates after an upload"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "Target of the site's CNAME record"
  value       = aws_cloudfront_distribution.this.domain_name
}
