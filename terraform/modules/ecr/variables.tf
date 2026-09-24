variable "name" {
  type        = string
  description = "Repository name. Must match the one the pipeline pushes to"
}

variable "retained_image_count" {
  type        = number
  description = "How many images to keep, which is how far back a rollback can go"
  default     = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
