# CloudFront distribution for private product images, served only through
# signed URLs.
#
# The bucket is unreachable directly: Origin Access Control is the only way in,
# and every request must additionally carry a signature the API produced. That
# is the difference from a public CDN — possessing the URL is not enough, the
# URL has to have been issued, and it expires.

# Origin Access Control replaces the older Origin Access Identity, which cannot
# sign requests to buckets using SSE-KMS.
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# The public half of the signing key pair. CloudFront verifies signatures
# against it; the API holds the private half and produces them.
resource "aws_cloudfront_public_key" "this" {
  name        = "${var.name}-signing-key"
  comment     = "Verifies signed URLs issued by the API"
  encoded_key = var.signing_public_key_pem
}

# A distribution trusts key groups, not individual keys. The indirection is what
# makes rotation possible: a second key can be added, clients migrate, and the
# first is removed without ever having a window where no key is valid.
resource "aws_cloudfront_key_group" "this" {
  name  = "${var.name}-key-group"
  items = [aws_cloudfront_public_key.this.id]
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name = "${var.name}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }

  custom_headers_config {
    items {
      header = "Cross-Origin-Resource-Policy"
      # The storefront loads these images from a different origin.
      value    = "cross-origin"
      override = true
    }
  }
}

# No WAF attached, and this is a cost decision rather than an oversight. A web
# ACL is around 6 to 10 USD/month with the managed rule set. What it would add
# here is limited: the distribution already rejects anything without a valid
# signature, so an unauthenticated request never reaches the origin. Recorded as
# an open decision rather than silently suppressed.
#trivy:ignore:AWS-0011
resource "aws_cloudfront_distribution" "this" {
  enabled     = true
  comment     = var.name
  price_class = var.price_class
  aliases     = var.aliases

  origin {
    origin_id                = "s3-assets"
    domain_name              = var.s3_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Without this a signature is optional, which is the whole control. An
    # unsigned request is rejected at the edge, before the origin is touched.
    trusted_key_groups = [aws_cloudfront_key_group.this.id]

    # AWS managed CachingOptimized. Signed URLs vary by signature, but the
    # signature travels in the query string and is deliberately not part of the
    # cache key — otherwise every issued URL would be a separate cache entry and
    # the cache would never hit.
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.acm_certificate_arn == null ? "TLSv1" : "TLSv1.2_2021"
  }

  tags = var.tags
}
