output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  description = "Point the DNS record here before running add-api.sh"
  value       = aws_eip.this.public_ip
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Grant private-tier resources access from this group only"
  value       = aws_security_group.this.id
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}
