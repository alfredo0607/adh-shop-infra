variable "project" {
  type    = string
  default = "adh-shop"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

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
  description = "SSH public key. Leave null to disable SSH and use Session Manager"
  default     = null
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "Source ranges permitted on port 22. Empty closes SSH entirely"
  default     = []
}
