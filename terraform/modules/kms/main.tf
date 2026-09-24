# Customer managed key for encrypting the asset bucket.
#
# An owned key rather than the AWS managed default: permission to decrypt lives
# in a key policy that can be audited and revoked, and every use is recorded in
# CloudTrail. The product images are served only through signed URLs, so the
# bucket is not public and the key is the second control behind that.

resource "aws_kms_key" "this" {
  description             = var.description
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias_name}"
  target_key_id = aws_kms_key.this.key_id
}
