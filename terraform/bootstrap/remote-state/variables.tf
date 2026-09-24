variable "project" {
  type        = string
  description = "Prefix for every resource name in this project"
  default     = "adh-shop"
}

variable "region" {
  type        = string
  description = "AWS region for the state bucket"
  default     = "us-east-1"
}
