variable "name" {
  type = string
}

variable "point_in_time_recovery" {
  type        = bool
  description = "Continuous backups. Costs roughly the size of the table again"
  default     = true
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
