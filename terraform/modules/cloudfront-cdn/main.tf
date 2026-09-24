# CloudFront distribution serving the single page application from a private
# S3 bucket, and optionally proxying the API under the same origin.

# Origin Access Control replaces the older Origin Access Identity. OAI cannot
# sign requests to buckets using SSE-KMS and is no longer the recommended path.
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Security headers applied at the edge, so every response carries them whether
# or not the origin bothered to set them. Applying them here rather than in the
# application means a new origin cannot silently arrive without them.
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

    xss_protection {
      protection = true
      mode_block = true
      override   = true
    }

    # 'unsafe-inline' for styles is what a bundler-produced SPA needs; scripts
    # are restricted to self, which is the half that actually stops injected
    # code from running.
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data: https:",
        "font-src 'self' data:",
        "connect-src 'self' ${var.connect_src_extra}",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
      ])
      override = true
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

# The bundle's filenames carry a content hash, so anything under /assets can be
# cached effectively forever. index.html must not be, or a deploy would take a
# day to become visible.
resource "aws_cloudfront_cache_policy" "immutable_assets" {
  name        = "${var.name}-immutable-assets"
  default_ttl = 31536000
  min_ttl     = 31536000
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

# No WAF attached, and this is a cost decision rather than an oversight.
#
# A web ACL costs about 5 USD/month plus 1 USD per rule and 0.60 USD per million
# requests, so the managed core rule set lands around 6 to 10 USD/month — on a
# project whose entire remaining footprint is close to free.
#
# What is given up: edge filtering of injection and cross-site scripting
# attempts, and rate-based blocking by IP before a request ever reaches the
# origin. The first matters less here than the scanner assumes — the data store
# is DynamoDB, so there is no SQL to inject, and the API rejects unknown
# properties at the boundary. The second is a genuine gap, and a rate-based WAF
# rule would solve distributed rate limiting more cleanly than an in-process
# counter or a cache in the private subnet, because it applies before the
# request is billed or served.
#
# Attaching one is a single argument once the cost is accepted. Recorded as an
# open decision rather than silently suppressed.
#trivy:ignore:AWS-0011
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = var.name
  default_root_object = "index.html"
  price_class         = var.price_class
  aliases             = var.aliases

  # ── SPA origin ──────────────────────────────────────────────────────────────
  origin {
    origin_id                = "s3-spa"
    domain_name              = var.s3_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  # ── API origin ──────────────────────────────────────────────────────────────
  #
  # Optional. Serving the API under the same domain as the SPA means the browser
  # never issues a cross-origin request: no preflight, no Access-Control
  # headers, and one fewer thing to misconfigure. It also puts the API behind
  # the same security headers and the same TLS policy.
  dynamic "origin" {
    for_each = var.api_origin_domain_name == null ? [] : [1]

    content {
      origin_id   = "api"
      domain_name = var.api_origin_domain_name

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
        origin_read_timeout    = 30
      }
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-spa"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed CachingOptimized
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    target_origin_id       = "s3-spa"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = aws_cloudfront_cache_policy.immutable_assets.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.api_origin_domain_name == null ? [] : [1]

    content {
      path_pattern           = "/api/*"
      target_origin_id       = "api"
      viewer_protocol_policy = "https-only"
      allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      # AWS managed CachingDisabled. An API response cached at the edge would
      # serve one customer's transaction to another.
      cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      # AWS managed AllViewerExceptHostHeader: forwards headers, cookies and
      # query strings, but lets the origin see its own hostname, which nginx
      # needs to select the right virtual host.
      origin_request_policy_id   = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
      response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
    }
  }

  # Client-side routing: a deep link such as /checkout/summary does not exist as
  # an object, so S3 answers 403. Rewriting to index.html with a 200 lets the
  # router handle it. Without this, refreshing any page but the root is an error.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Without a custom domain the default CloudFront certificate is used, which
    # is free and already valid for *.cloudfront.net.
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.acm_certificate_arn == null ? "TLSv1" : "TLSv1.2_2021"
  }

  tags = var.tags
}
