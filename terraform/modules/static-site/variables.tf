variable "name" {
  type        = string
  description = "Prefix for the CloudFront resources"
}

variable "bucket_name" {
  type = string
}

variable "content_security_policy" {
  type        = string
  description = "Sent on every response. Build it from the origins the app actually calls"
}

variable "aliases" {
  type        = list(string)
  description = "Custom domains. Requires acm_certificate_arn"
  default     = []
}

variable "acm_certificate_arn" {
  type        = string
  description = "MUST be issued in us-east-1: CloudFront reads certificates only from there"
  default     = null
}

variable "price_class" {
  type    = string
  default = "PriceClass_100"
}

variable "tags" {
  type    = map(string)
  default = {}
}
