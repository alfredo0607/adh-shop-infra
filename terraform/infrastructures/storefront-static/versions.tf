terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration, like every stack: the bucket is supplied at init
  # time by scripts/tf-init.sh, so this file carries no account-specific value.
  backend "s3" {
    key          = "storefront-static/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}

# us-east-1 is not only the default region here: CloudFront reads certificates
# only from there, so the stack must stay in it for the certificate to be usable.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "storefront-static"
    }
  }
}
