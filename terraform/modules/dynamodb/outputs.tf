output "table_name" {
  value = aws_dynamodb_table.this.name
}

output "table_arn" {
  value = aws_dynamodb_table.this.arn
}

output "table_index_arns" {
  description = "Needed when granting Query on an index: the table ARN alone does not cover it"
  value       = ["${aws_dynamodb_table.this.arn}/index/*"]
}
