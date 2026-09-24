output "public_ip" {
  description = "Create the DNS A record against this address before running add-api.sh"
  value       = module.container_host.public_ip
}

output "ecr_repository_url" {
  description = "Push target for the CI pipeline"
  value       = module.ecr.repository_url
}

output "scripts_bucket" {
  value = aws_s3_bucket.scripts.id
}

output "security_group_id" {
  description = "Allow this group when granting access to private-tier resources"
  value       = module.container_host.security_group_id
}

output "next_steps" {
  value = <<-EOT
    1. Point a DNS A record at ${module.container_host.public_ip}
    2. Publish configuration:  ./add-keys.sh app.env
    3. Publish the site:       ./add-api.sh <subdomain> 3000 <email>
    4. Deploy:                 ./deploy.sh ${module.ecr.repository_url}:<sha> <app>
  EOT
}

output "role_name" {
  description = "Consumed by the cache stack to attach elasticache:Connect"
  value       = module.container_host.role_name
}

output "role_arn" {
  value = module.container_host.role_arn
}
