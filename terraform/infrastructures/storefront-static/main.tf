# The storefront: a static build in a private bucket, served by its own
# CloudFront distribution on its own domain.
#
# A separate distribution from the image CDN rather than a second behaviour on
# it. The image distribution requires a signature on every request; the site
# must not. Their caching and headers pull in opposite directions, and a
# mistake configuring one would put the other at risk. A distribution has no
# fixed cost, so separating them is free.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# The image CDN's domain, for img-src. Read from the API stack rather than
# copied, so a replaced distribution cannot leave the policy blocking images.
data "terraform_remote_state" "api" {
  backend = "s3"

  config = {
    bucket = "${var.project}-terraform-state-${local.account_id}"
    key    = "container-api-ec2/terraform.tfstate"
    region = var.region
  }
}

locals {
  # Every origin the storefront talks to, and nothing else.
  #  - style-src 'unsafe-inline': the dialogs' scroll lock injects a <style>
  #    element at runtime. Styles cannot run code; scripts stay 'self' only.
  #  - img-src data: small icons are inlined into the bundle by the build.
  content_security_policy = join("; ", [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https://${data.terraform_remote_state.api.outputs.cdn_domain}",
    "font-src 'self'",
    "connect-src 'self' ${join(" ", concat([var.api_origin], var.payment_gateway_origins))}",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
  ])
}

# ── Certificate ───────────────────────────────────────────────────────────────
#
# Validated through DNS, which lives in Cloudflare, outside this account. The
# first apply therefore stops here (see the README): it creates the certificate,
# prints the validation record, and the distribution waits until that record
# exists and ACM has issued the certificate.

resource "aws_acm_certificate" "site" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "site" {
  certificate_arn = aws_acm_certificate.site.arn

  timeouts {
    create = "30m"
  }
}

# ── Site ──────────────────────────────────────────────────────────────────────

module "site" {
  source = "../../modules/static-site"

  name                    = "${var.project}-storefront"
  bucket_name             = "${var.project}-storefront-${local.account_id}"
  content_security_policy = local.content_security_policy

  aliases             = [var.domain_name]
  acm_certificate_arn = aws_acm_certificate_validation.site.certificate_arn
  price_class         = var.price_class
}

# ── Deployment identity ───────────────────────────────────────────────────────

module "deploy_role" {
  source = "../../modules/iam-github-static-deploy"

  role_name = "${var.project}-storefront-deploy"
  allowed_subjects = [
    "repo:${var.github_repository_owner}@${var.github_owner_id}/${var.github_repository_name}@${var.github_repository_id}:environment:${var.deploy_environment}",
  ]

  bucket_arn       = module.site.bucket_arn
  distribution_arn = module.site.distribution_arn
}
