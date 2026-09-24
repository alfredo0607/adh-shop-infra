output "table_name" {
  value = module.dynamodb.table_name
}

output "table_arn" {
  value = module.dynamodb.table_arn
}

output "table_index_arns" {
  value = module.dynamodb.table_index_arns
}
