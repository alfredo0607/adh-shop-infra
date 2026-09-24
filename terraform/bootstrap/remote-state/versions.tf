terraform {
  # Pinned to a minor range. ">= 1.4.0" would accept a future 2.x with breaking
  # changes, which is not what "supported" means.
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # No `profile` here on purpose. Hardcoding one ties the code to a single
  # developer's machine and breaks in CI, where that profile does not exist.
  # Credentials come from the default chain: environment, profile or OIDC role.

  # Applied to every resource this provider creates, so nothing can be left
  # untagged by forgetting to pass a tags argument.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap/remote-state"
    }
  }
}
