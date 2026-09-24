variable "name" {
  type = string
}

variable "s3_bucket_regional_domain_name" {
  type        = string
  description = "Origin domain of the bucket holding the built SPA"
}

variable "api_origin_domain_name" {
  type        = string
  description = "API hostname to serve under /api/*. Null disables the behaviour and leaves the SPA making cross-origin calls"
  default     = null
}

variable "aliases" {
  type        = list(string)
  description = "Custom domains. Requires acm_certificate_arn"
  default     = []
}

variable "acm_certificate_arn" {
  type        = string
  description = "Certificate for the aliases. MUST be issued in us-east-1: CloudFront reads certificates from that region only"
  default     = null
}

variable "connect_src_extra" {
  type        = string
  description = "Extra origins the browser may call, for the payment gateway's tokenisation endpoint"
  default     = ""
}

variable "price_class" {
  type        = string
  description = "PriceClass_100 covers North America and Europe at the lowest cost"
  default     = "PriceClass_100"
}

variable "tags" {
  type    = map(string)
  default = {}
}
