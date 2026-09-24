# Container host stack: ECR, the scripts bucket, and the EC2 instance that runs
# nginx in front of the application containers.

data "aws_caller_identity" "current" {}

# Network and data are read from the state of the stacks that own them, not
# rebuilt as strings.
#
# The alternative — recomposing a name like "${var.project}-private-1" in this
# file — is a contract enforced only by whoever remembers it. Rename the subnet
# on one side and this stack keeps applying cleanly while pointing at something
# that no longer exists. An output is checked by Terraform; a string is not.

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "data_store" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "data-store/terraform.tfstate"
    region = var.region
  }
}

locals {
  name           = "${var.project}-container-host"
  parameter_path = "/${var.project}"

  # The public tier: this host must be reachable from the internet and needs an
  # inbound connection on port 80 for the ACME challenge.
  subnet_id = data.terraform_remote_state.network.outputs.public_subnet_ids[0]

  table_arn = data.terraform_remote_state.data_store.outputs.table_arn
}

# ── ECR ───────────────────────────────────────────────────────────────────────

module "ecr" {
  source = "../../modules/ecr"
  name   = var.ecr_repo_name
}

# ── Scripts bucket ────────────────────────────────────────────────────────────
#
# Holds the management scripts only. Application secrets are NOT stored here:
# they live in Parameter Store, so a mistake in this bucket's policy cannot
# expose a payment credential.

resource "aws_s3_bucket" "scripts" {
  bucket = "${var.project}-scripts-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Uploaded by Terraform so the scripts on the host always match what is in this
# repository. etag triggers a re-upload whenever the file changes.
resource "aws_s3_object" "scripts" {
  for_each = fileset("${path.module}/../../scripts/container-api-ec2", "*.sh")

  bucket = aws_s3_bucket.scripts.id
  key    = "scripts/${each.value}"
  source = "${path.module}/../../scripts/container-api-ec2/${each.value}"
  etag   = filemd5("${path.module}/../../scripts/container-api-ec2/${each.value}")

  content_type = "text/x-shellscript"
}

# ── Container host ────────────────────────────────────────────────────────────

module "container_host" {
  source = "../../modules/ec2-container-host"

  name       = local.name
  region     = var.region
  account_id = data.aws_caller_identity.current.account_id

  vpc_id    = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id = local.subnet_id

  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  public_key        = var.ssh_public_key
  allowed_ssh_cidrs = var.allowed_ssh_cidrs

  ecr_repository_arn = module.ecr.repository_arn
  scripts_bucket_arn = aws_s3_bucket.scripts.arn
  parameter_path     = local.parameter_path

  dynamodb_table_arns = [local.table_arn, "${local.table_arn}/index/*"]

  user_data_base64 = base64encode(templatefile(
    "${path.module}/../../user-data/container-api-ec2/bootstrap.sh",
    {
      project        = var.project
      region         = var.region
      scripts_bucket = aws_s3_bucket.scripts.id
      parameter_path = local.parameter_path
    }
  ))

  # The scripts must exist in the bucket before the instance boots and tries to
  # download them.
  depends_on = [aws_s3_object.scripts]
}
