variable "project" {
  type    = string
  default = "adh-shop"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "api_origin_domain_name" {
  type        = string
  description = "Hostname of the API, served under /api/*. Null leaves the SPA making cross-origin calls"
  default     = null
}

variable "payment_gateway_origin" {
  type        = string
  description = "Origin the browser may call for card tokenisation, added to connect-src"
  default     = ""
}

variable "aliases" {
  type        = list(string)
  description = "Custom domains. Requires acm_certificate_arn"
  default     = []
}

variable "acm_certificate_arn" {
  type        = string
  description = "Must be issued in us-east-1: CloudFront reads certificates from that region only"
  default     = null
}

variable "price_class" {
  type    = string
  default = "PriceClass_100"
}
