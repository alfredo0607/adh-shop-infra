variable "name" {
  type        = string
  description = "Cache name. Also the signing host for the IAM auth token"
}

variable "description" {
  type    = string
  default = "Distributed rate limiter backing store"
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr_block" {
  type        = string
  description = "Bounds the cache's egress to the VPC"
}

variable "subnet_ids" {
  type        = list(string)
  description = "PRIVATE subnets. This must not be reachable from the internet"
}

variable "client_security_group_ids" {
  type        = list(string)
  description = "Groups allowed to connect. Empty makes the cache unreachable"
  default     = []
}

variable "iam_user_name" {
  type        = string
  description = "Valkey user authenticated through IAM. user_id must equal user_name"
}

variable "key_prefix" {
  type        = string
  description = "Key namespace the IAM user is confined to"
  default     = "ratelimit:"
}

variable "cache_port" {
  type    = number
  default = 6379
}

variable "major_engine_version" {
  type    = string
  default = "8"
}

variable "max_storage_gb" {
  type        = number
  description = "Storage ceiling. A rate limiter needs a fraction of a gigabyte"
  default     = 1
}

variable "max_ecpu_per_second" {
  type        = number
  description = "Compute ceiling, so a traffic spike throttles instead of billing without limit"
  default     = 5000
}

variable "tags" {
  type    = map(string)
  default = {}
}
