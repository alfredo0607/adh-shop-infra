variable "role_name" {
  type = string
}

variable "allowed_subjects" {
  type        = list(string)
  description = <<-EOT
    Which workflow runs may assume this role, as GitHub OIDC subject claims.

    e.g. repo:owner/name:ref:refs/heads/main

    Never "repo:owner/name:*": that would let a pull request from a fork deploy,
    since a fork's workflow runs with the base repository's subject prefix.
  EOT
}

variable "ecr_repository_arn" {
  type = string
}

variable "instance_arn" {
  type        = string
  description = "The instance the deployment may send commands to, and no other"
}

variable "region" {
  type = string
}

variable "partition" {
  type    = string
  default = "aws"
}

variable "create_oidc_provider" {
  type        = bool
  description = "False when the account already has GitHub's provider registered; there can only be one"
  default     = true
}

variable "thumbprints" {
  type        = list(string)
  description = "Certificate thumbprints for GitHub's OIDC endpoint"
  default     = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
