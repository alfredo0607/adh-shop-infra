# Creates the S3 bucket that holds the Terraform state for every other stack.
#
# This is the chicken-and-egg stack: it cannot itself use a remote backend,
# because the backend does not exist until this has been applied. Its own state
# is local and disposable — the bucket is trivially recreated, and nothing else
# depends on this state file.
#
# Apply once, then run `terraform init -backend-config=...` in the other stacks.

locals {
  bucket_name = "${var.project}-terraform-state-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # State is the map between code and real infrastructure. Losing it means
  # importing every resource by hand, so deletion must be deliberate.
  lifecycle {
    prevent_destroy = true
  }
}

# Every apply writes a new version. This is the difference between "someone
# corrupted the state an hour ago" being a five-minute rollback or a full day
# of manual imports.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State stores resource attributes in plaintext, including anything read from
# Secrets Manager or Parameter Store. Encryption at rest is not optional.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old versions accumulate on every apply. Ninety days is long enough to recover
# from a mistake nobody noticed immediately, short enough not to pay to store
# years of noise.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Rejects any request that is not TLS. Without this, a misconfigured client can
# push state over plaintext HTTP.
resource "aws_s3_bucket_policy" "enforce_tls" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}
