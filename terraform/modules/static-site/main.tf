# A single-page application served from a private bucket through CloudFront.
#
# Unlike the image CDN, nothing here is signed: the storefront is public by
# definition. What this module adds instead is what a browser application needs
# from its host — HTTPS on its own domain, a Content-Security-Policy, deep links
# that load the app instead of a 404, and caching that never serves a stale
# index.html pointing at bundles that no longer exist.

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# AWS managed encryption is deliberate, as for the scripts bucket. The bucket
# holds the built storefront: files every visitor downloads, built from a public
# repository. A customer managed key would add a monthly charge, a key policy
# and a KMS call on every cache miss, and protect nothing that is not already
# public.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# A deployment replaces every file. Versioning turns rolling back a bad release
# into restoring the previous versions, without rebuilding it.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-old-releases"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Routes that belong to the app (/checkout, /orders/abc) are not files in the
# bucket. Without this, a reload or a shared link on one of them is a 403 from
# S3. A path whose last segment has no extension is an app route and gets
# index.html; anything else is a real file, and a missing one stays an error.
#
# A function rather than custom error responses mapping 403/404 to index.html:
# those would also answer a missing /assets/app-1234.js with HTML and a 200,
# which the browser then fails to run as a script — the worst kind of failure
# to debug after a release.
resource "aws_cloudfront_function" "spa_routes" {
  name    = "${var.name}-spa-routes"
  runtime = "cloudfront-js-2.0"
  comment = "Serves index.html for app routes"
  publish = true
  code    = file("${path.module}/spa-routes.js")
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name = "${var.name}-security-headers"

  security_headers_config {
    content_security_policy {
      content_security_policy = var.content_security_policy
      override                = true
    }

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
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=()"
      override = true
    }
  }
}

# No WAF, for the same reason as the image CDN: 6 to 10 USD/month for a site of
# static files, where the requests that matter go to the API, which sits behind
# Cloudflare. Recorded as a decision rather than silently suppressed.
#trivy:ignore:AWS-0011
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = var.name
  price_class         = var.price_class
  aliases             = var.aliases
  default_root_object = "index.html"
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  origin {
    origin_id                = "s3-site"
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed CachingOptimized. It honours the Cache-Control each file is
    # uploaded with: hashed bundles are immutable for a year, index.html must
    # be revalidated. The deployment sets those; see the storefront's workflow.
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_routes.arn
    }
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

# Only this distribution may read the bucket. Without the SourceArn condition,
# any CloudFront distribution in any account could.
data "aws_iam_policy_document" "read" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "read" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.read.json

  # The policy is rejected while public access settings are still being applied.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
