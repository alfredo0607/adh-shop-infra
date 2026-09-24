variable "project" {
  type    = string
  default = "adh-shop"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket" {
  type        = string
  description = "Bucket created by bootstrap/remote-state"
}

variable "key_prefix" {
  type        = string
  description = "Key namespace the cache identity is confined to"
  default     = "ratelimit:"
}

variable "max_storage_gb" {
  type        = number
  description = "Storage ceiling. Counters need a fraction of this"
  default     = 1
}

variable "max_ecpu_per_second" {
  type        = number
  description = "Compute ceiling, so a spike throttles rather than billing without limit"
  default     = 5000
}
