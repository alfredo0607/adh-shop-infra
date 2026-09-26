variable "project" {
  type    = string
  default = "adh-shop"
}

variable "region" {
  type    = string
  default = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "CloudFront reads certificates only from us-east-1."
  }
}

# ── Site ──────────────────────────────────────────────────────────────────────

variable "domain_name" {
  type        = string
  description = "The storefront's host. Must match the origin the API allows through CORS"
  default     = "adh-shop.alfredo-dominguez.dev"
}

variable "api_origin" {
  type        = string
  description = "The API the storefront calls, as scheme and host"
  default     = "https://adh-api.alfredo-dominguez.dev"
}

variable "payment_gateway_origins" {
  type        = list(string)
  description = <<-EOT
    Origins the browser sends the card to for tokenisation: the host of
    cardTokenizationUrl in GET /payment-terms. Without it in connect-src, the
    Content-Security-Policy blocks every payment.
  EOT

  validation {
    condition     = alltrue([for origin in var.payment_gateway_origins : can(regex("^https://[a-z0-9.-]+$", origin))])
    error_message = "Each origin must be https://host, with no path or trailing slash."
  }
}

variable "price_class" {
  type    = string
  default = "PriceClass_100"
}

# ── Deployment identity ───────────────────────────────────────────────────────
#
# Read with:
#   gh api repos/<owner>/<repo> --jq '{repo: .id, owner: .owner.id}'

variable "github_repository_owner" {
  type = string
}

variable "github_repository_name" {
  type = string
}

variable "github_owner_id" {
  type = number
}

variable "github_repository_id" {
  type = number
}

variable "deploy_environment" {
  type    = string
  default = "production"
}
