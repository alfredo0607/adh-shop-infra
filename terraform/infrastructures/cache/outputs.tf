output "endpoint_address" {
  value = module.valkey.endpoint_address
}

output "endpoint_port" {
  value = module.valkey.endpoint_port
}

output "iam_user_name" {
  value = module.valkey.iam_user_name
}

output "security_group_id" {
  value = module.valkey.security_group_id
}
