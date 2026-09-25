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

variable "key_pair_name" {
  type        = string
  description = <<-EOT
    Name of an existing EC2 key pair to attach.

    Created in the AWS console or with `aws ec2 create-key-pair`, which
    generates the pair and hands back the private half once. Referencing it by
    name keeps the private key out of Terraform: generating it here would write
    it into state, where it outlives the moment it was needed and is far harder
    to rotate than a key pair that can simply be replaced.

    Null attaches none, leaving Session Manager as the way in.
  EOT
  default     = null
}

variable "https_ingress_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-EOT
    Source ranges permitted to reach port 443.

    Open by default. Behind a CDN, pass the CDN's ranges instead: anything else
    lets a caller reach the origin directly, skipping the CDN's protection and
    choosing its own X-Forwarded-For, which is what the rate limiter trusts.
  EOT

  validation {
    condition     = length(var.https_ingress_cidrs) > 0 && alltrue([for cidr in var.https_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "https_ingress_cidrs must be a non-empty list of IPv4 CIDR blocks. An empty list would take the site offline."
  }
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
