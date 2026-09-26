variable "role_name" {
  type = string
}

variable "allowed_subjects" {
  type        = list(string)
  description = "GitHub OIDC subject claims allowed to assume the role, matched exactly"
}

variable "bucket_arn" {
  type        = string
  description = "The only bucket the role may write to"
}

variable "distribution_arn" {
  type        = string
  description = "The only distribution the role may invalidate"
}

variable "tags" {
  type    = map(string)
  default = {}
}
