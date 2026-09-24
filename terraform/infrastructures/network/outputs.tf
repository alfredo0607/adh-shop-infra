output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Consumed by the container stack"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Consumed by anything that must not be reachable from the internet"
  value       = module.vpc.private_subnet_ids
}
