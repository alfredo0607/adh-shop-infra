variable "name" {
  type        = string
  description = "Name prefix for every resource of this host"
}

variable "region" {
  type = string
}

variable "account_id" {
  type        = string
  description = "Used to scope IAM resource ARNs instead of using a wildcard"
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type        = string
  description = "A PUBLIC subnet: nginx must be reachable and certbot needs inbound :80"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "root_volume_size" {
  type    = number
  default = 20
}

variable "public_key" {
  type        = string
  description = "SSH public key. Null disables SSH entirely in favour of Session Manager"
  default     = null
  sensitive   = false
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = <<-EOT
    Source ranges permitted to reach port 22. Empty closes the port entirely.

    0.0.0.0/0 is accepted. It attracts credential-stuffing traffic from the
    moment the address is reachable, so it is worth narrowing when practical —
    but that is the operator's call, not this module's. Refusing it outright
    only pushed the decision somewhere less visible.
  EOT
  default     = []
}

variable "ecr_repository_arn" {
  type        = string
  description = "Repository the host is allowed to pull from"
}

variable "scripts_bucket_arn" {
  type        = string
  description = "Bucket holding the management scripts, read only"
}

variable "parameter_path" {
  type        = string
  description = "Parameter Store prefix this host may read, e.g. /adh-shop"
}

variable "user_data_base64" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "dynamodb_table_arns" {
  type        = list(string)
  description = "Tables and indexes the application may read and write"
  default     = []
}
