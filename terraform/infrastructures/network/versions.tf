terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration. The bucket is created by bootstrap/remote-state and
  # supplied at init time, so this file carries no account-specific value:
  #   terraform init -backend-config=../../backend.hcl
  backend "s3" {
    key = "network/terraform.tfstate"

    # Native S3 locking, available since Terraform 1.10. The separate DynamoDB
    # lock table that older guides require is no longer needed.
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "network"
    }
  }
}
