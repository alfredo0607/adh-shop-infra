output "bucket_name" {
  description = "Sync the built SPA here"
  value       = module.s3.bucket_id
}

output "distribution_id" {
  description = "Invalidate this after every front-end deployment"
  value       = module.cloudfront.distribution_id
}

output "domain_name" {
  value = module.cloudfront.domain_name
}

output "deploy_command" {
  value = <<-EOT
    aws s3 sync dist/ s3://${module.s3.bucket_id}/ --delete
    aws cloudfront create-invalidation \
      --distribution-id ${module.cloudfront.distribution_id} \
      --paths "/index.html"
  EOT
}
