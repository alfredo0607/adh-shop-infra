variable "name" {
  type        = string
  description = "Names the queue, the dead-letter queue, the function and its role"
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "partition" {
  type    = string
  default = "aws"
}

variable "build_dir" {
  type        = string
  description = "The directory build.sh prepared: source plus production dependencies"
}

variable "parameter_path" {
  type        = string
  description = "Holds MAIL_USER and MAIL_PASSWORD. Must be outside the API's path, or the API would receive them too"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.-]+$", var.parameter_path))
    error_message = "One level, starting with a slash and without a trailing one, e.g. /adh-shop-mailer."
  }
}

variable "from_name" {
  type    = string
  default = "ADH Shop"
}

variable "storefront_url" {
  type        = string
  description = "Where the email's link to the order points, without a trailing slash"
}

variable "timeout_seconds" {
  type    = number
  default = 30
}

variable "max_receive_count" {
  type        = number
  description = "Attempts before a message moves to the dead-letter queue"
  default     = 3
}

variable "tags" {
  type    = map(string)
  default = {}
}
