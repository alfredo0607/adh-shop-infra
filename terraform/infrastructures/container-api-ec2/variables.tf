variable "project" {
  type    = string
  default = "adh-shop"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Internet-facing tier: the container host"
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Isolated tier: no route to the internet"
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "enable_flow_logs" {
  type        = bool
  description = "Record rejected traffic, so reachability is answerable after the fact"
  default     = true
}

# ── Host ──────────────────────────────────────────────────────────────────────

variable "ecr_repo_name" {
  type        = string
  description = "Must match the repository the CI pipeline pushes to"
  default     = "adh-shop-api"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "root_volume_size" {
  type    = number
  default = 20
}

variable "key_pair_name" {
  type        = string
  description = <<-EOT
    Name of an EC2 key pair that already exists in this account.

    Create it in the console or with:
      aws ec2 create-key-pair --key-name adh-shop --query KeyMaterial         --output text > adh-shop.pem && chmod 400 adh-shop.pem

    AWS generates the pair and returns the private half once, so it never
    reaches Terraform state. Null attaches none.
  EOT
  default     = null
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = <<-EOT
    Source ranges permitted on port 22.

    0.0.0.0/0 is accepted. It attracts credential-stuffing traffic from the
    moment the address is reachable, which is a real cost and a deliberate
    choice rather than a mistake — narrow it to a single address whenever that
    is practical. An empty list closes the port entirely; Session Manager still
    works, because it needs no inbound rule at all.
  EOT
  default     = ["0.0.0.0/0"]
}

# ── Cache ─────────────────────────────────────────────────────────────────────

variable "enable_cache" {
  type        = bool
  description = <<-EOT
    Provision Valkey for the rate limiter.

    Off by default: serverless bills a minimum storage footprint whether or not
    anything uses it, roughly 6 to 7 USD a month. With a single instance the
    limiter's in-process counters are correct, so this only becomes necessary
    with a second one.
  EOT
  default     = false
}

variable "cache_key_prefix" {
  type    = string
  default = "ratelimit:"
}

variable "cache_max_storage_gb" {
  type        = number
  description = "Ceiling, not a target. Counters need a fraction of this"
  default     = 1
}

variable "cache_max_ecpu_per_second" {
  type        = number
  description = "Ceiling, so a traffic spike throttles rather than billing without limit"
  default     = 5000
}

# ── Image CDN ─────────────────────────────────────────────────────────────────

variable "signing_public_key_pem" {
  type        = string
  description = <<-EOT
    PEM public key CloudFront verifies signed URLs against.

    Null reads public_key.pem from the stack directory, which is where the
    reference implementation keeps it. A public key is not a secret, so it is
    committed; its private half goes to the scripts bucket and from there to
    Parameter Store.
  EOT
  default     = null
}

variable "cdn_aliases" {
  type    = list(string)
  default = []
}

variable "cdn_acm_certificate_arn" {
  type        = string
  description = "MUST be issued in us-east-1: CloudFront reads certificates only from there"
  default     = null
}

variable "cdn_price_class" {
  type    = string
  default = "PriceClass_100"
}

# ── Deployment ────────────────────────────────────────────────────────────────

variable "github_repository_owner" {
  type        = string
  description = "Account that owns the repository allowed to deploy. Null creates no deploy role"
  default     = null
}

variable "github_repository_name" {
  type    = string
  default = null
}

# GitHub signs OIDC subjects with immutable ids rather than names, so a renamed
# or re-registered repository cannot inherit this trust. Read them once with:
#   gh api repos/<owner>/<name> --jq '{repo: .id, owner: .owner.id}'
variable "github_owner_id" {
  type    = number
  default = null
}

variable "github_repository_id" {
  type    = number
  default = null
}

variable "deploy_environment" {
  type        = string
  description = <<-EOT
    GitHub deployment environment permitted to assume the role.

    The branch restriction lives on the environment itself, as a deployment
    branch policy, rather than in the trust policy — a job declaring an
    environment gets a subject naming it instead of the ref, so there is no ref
    left here to match against.
  EOT
  default     = "production"
}

variable "create_oidc_provider" {
  type        = bool
  description = "False when the account already registers GitHub's provider; only one may exist"
  default     = true
}

variable "storefront_origins" {
  type        = list(string)
  description = "Origins allowed to call the API from a browser: scheme and host, no path or trailing slash"
  default     = ["https://adh-shop.alfredo-dominguez.dev"]

  validation {
    condition     = alltrue([for origin in var.storefront_origins : can(regex("^https://[a-z0-9.-]+$", origin))])
    error_message = "Each origin must be https://host, with no path, port or trailing slash. A browser sends the origin in exactly that form, and CORS compares it character for character."
  }
}
