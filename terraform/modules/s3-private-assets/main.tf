# Private bucket serving content through CloudFront only.
#
# The bucket itself is never public. CloudFront reaches it with Origin Access
# Control, so the only path to an object is through the distribution — which
# means the TLS, the security headers and the caching cannot be bypassed by
# addressing the bucket directly.

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

# AWS managed encryption. The objects here are a compiled front-end bundle that
# is served publicly through the CDN anyway, so a customer managed key would add
# a monthly charge and a key policy to maintain and protect nothing.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# A deployment overwrites every file. Versioning makes rolling back a bad
# front-end release a matter of restoring versions rather than rebuilding.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-old-bundles"
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

# The bucket policy is deliberately NOT defined here.
#
# It needs the distribution ARN, while the distribution needs this bucket's
# domain name. Expressing both as module inputs creates a cycle Terraform
# refuses to plan. The policy therefore lives in the stack, where both values
# are already in scope and the dependency runs one way.
