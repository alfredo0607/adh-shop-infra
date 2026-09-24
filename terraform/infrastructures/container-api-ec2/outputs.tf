output "public_ip" {
  description = "Point the DNS A record at this address before running add-api.sh"
  value       = module.container_host.public_ip
}

output "ssh_command" {
  description = "Only useful when ssh_public_key was supplied"
  value       = "ssh ec2-user@${module.container_host.public_ip}"
}

output "ecr_repository_url" {
  description = "Push target for the CI pipeline"
  value       = module.ecr.repository_url
}

output "table_name" {
  value = module.dynamodb.table_name
}

output "scripts_bucket" {
  value = aws_s3_bucket.scripts.id
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "security_group_id" {
  value = module.container_host.security_group_id
}

output "cache_endpoint" {
  description = "Null unless enable_cache is set"
  value       = var.enable_cache ? module.valkey[0].endpoint_address : null
}

output "next_steps" {
  value = <<-EOT
    1. Point a DNS A record at ${module.container_host.public_ip}
    2. Publish application secrets:  ./add-keys.sh app.env
    3. Publish the site over HTTPS:  ./add-api.sh <subdomain> 3000 <email>
    4. Deploy:                       ./deploy.sh ${module.ecr.repository_url}:<sha> <app>
  EOT
}
