output "queue_url" {
  description = "Where the API sends payment events"
  value       = aws_sqs_queue.this.id
}

output "queue_arn" {
  description = "Scopes the API's permission to send"
  value       = aws_sqs_queue.this.arn
}

output "dead_letter_queue_url" {
  value = aws_sqs_queue.dead_letter.id
}

output "function_name" {
  value = aws_lambda_function.this.function_name
}
