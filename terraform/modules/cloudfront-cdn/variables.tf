variable "name" {
  type = string
}

variable "s3_bucket_regional_domain_name" {
  type        = string
  description = "Origin domain of the bucket holding the images"
}

variable "signing_public_key_pem" {
  type        = string
  description = "PEM public key CloudFront verifies signatures against"
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
