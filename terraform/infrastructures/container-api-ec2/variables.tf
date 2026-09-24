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

variable "ssh_public_key" {
  type        = string
  description = "SSH public key. Null creates no key pair and leaves Session Manager as the only way in"
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
