output "state_bucket" {
  description = "Bucket holding the Terraform state of every other stack"
  value       = aws_s3_bucket.state.id
}

output "backend_config" {
  description = "Paste into backend.hcl, or pass with -backend-config"
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.id}"
    key          = "<stack-name>/terraform.tfstate"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
