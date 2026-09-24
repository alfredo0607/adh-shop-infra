variable "bucket_name" {
  type = string
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed key encrypting the objects. Null falls back to AWS managed encryption"
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
