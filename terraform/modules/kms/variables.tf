variable "alias_name" {
  type        = string
  description = "Alias, without the alias/ prefix"
}

variable "description" {
  type = string
}

variable "deletion_window_in_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
