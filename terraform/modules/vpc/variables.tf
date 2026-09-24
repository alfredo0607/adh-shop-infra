variable "name" {
  type        = string
  description = "Name prefix for every resource in this VPC"
}

variable "region" {
  type        = string
  description = "Region, needed to build the gateway endpoint service names"
}

variable "cidr_block" {
  type        = string
  description = "CIDR block of the VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs of the public tier: internet-facing workloads"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs of the private tier: no route to the internet"
}

variable "enable_flow_logs" {
  type        = bool
  description = "Record rejected traffic, so a reachability question is answerable after the fact"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags merged into every resource"
  default     = {}
}
