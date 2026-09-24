# Storefront delivery: a private S3 bucket holding the built SPA, served through
# CloudFront, with the API optionally proxied under the same origin.

data "aws_caller_identity" "current" {}

module "s3" {
  source      = "../../modules/s3-private-assets"
  bucket_name = "${var.project}-web-${data.aws_caller_identity.current.account_id}"
}

module "cloudfront" {
  source = "../../modules/cloudfront-cdn"

  name                           = "${var.project}-web"
  s3_bucket_regional_domain_name = module.s3.bucket_regional_domain_name

  # Serving the API under the same domain as the SPA removes cross-origin
  # requests entirely: no preflight, no Access-Control headers, and the API
  # inherits the same TLS policy and security headers as the front end.
  api_origin_domain_name = var.api_origin_domain_name

  # The browser tokenises the card directly against the payment gateway, so its
  # endpoint has to be allowed by the connect-src directive. It is configuration
  # rather than a constant: the host differs per environment, and the codebase
  # must not carry knowledge of the vendor.
  connect_src_extra = var.payment_gateway_origin

  aliases             = var.aliases
  acm_certificate_arn = var.acm_certificate_arn
  price_class         = var.price_class
}

# Defined here rather than in the bucket module: the policy needs the
# distribution ARN and the distribution needs the bucket domain, so expressing
# both as module inputs would be a cycle. In the stack both values are in scope
# and the dependency runs one way.
#
# Scoping by SourceArn matters. Without the condition, any CloudFront
# distribution in any AWS account could read this bucket.
data "aws_iam_policy_document" "cloudfront_read" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${module.s3.bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront.distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudfront_read" {
  bucket = module.s3.bucket_id
  policy = data.aws_iam_policy_document.cloudfront_read.json
}
