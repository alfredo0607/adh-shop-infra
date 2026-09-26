# Modules declare their own provider requirements. A module that relies on
# inheritance works by accident and cannot be reused outside this repository.
terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Zips the function's package.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}
