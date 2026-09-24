# The API platform, in one apply.
#
# Network, table, registry, host and optional cache live in a single stack
# rather than four. Splitting them was justified on blast radius — a mistake
# while deploying the application should not be able to touch routing — and
# that argument holds when separate teams own separate layers and change them
# at different rates. It does not hold here: one person owns all of it, there
# is one environment, and it is short-lived. The separation bought ceremony
# rather than safety, at the price of four applies in a fixed order that had to
# be remembered.
#
#   terraform apply
#
# The storefront CDN stays in its own stack. It shares nothing with this one —
# no VPC, no instance, no table — and only matters once the front end exists.

data "aws_caller_identity" "current" {}

locals {
  name           = "${var.project}-container-host"
  parameter_path = "/${var.project}"
  account_id     = data.aws_caller_identity.current.account_id
}

# ── Network ───────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  name       = var.project
  region     = var.region
  cidr_block = var.vpc_cidr

  # Public: the host. It must answer on 80/443, and certbot's HTTP-01 challenge
  # needs an inbound connection on port 80.
  public_subnet_cidrs = var.public_subnet_cidrs

  # Private: the cache. No route to an internet gateway at all.
  private_subnet_cidrs = var.private_subnet_cidrs

  enable_flow_logs = var.enable_flow_logs
}

# ── Data ──────────────────────────────────────────────────────────────────────

module "dynamodb" {
  source = "../../modules/dynamodb"
  name   = "${var.project}-store"
}

# ── Registry ──────────────────────────────────────────────────────────────────

module "ecr" {
  source = "../../modules/ecr"
  name   = var.ecr_repo_name
}

# ── Scripts bucket ────────────────────────────────────────────────────────────
#
# Holds the management scripts only. Application secrets live in Parameter
# Store, so a mistake in this bucket's policy cannot expose a payment
# credential.

resource "aws_s3_bucket" "scripts" {
  bucket = "${var.project}-scripts-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# AWS managed encryption is deliberate here, unlike the state bucket. This holds
# shell scripts that are already public in the repository, so a customer managed
# key would add a monthly charge and a key policy to maintain in exchange for
# nothing. Applying a control where it buys nothing is how teams learn to ignore
# their scanners.
#trivy:ignore:AWS-0132
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

# Uploaded by Terraform so the scripts on the host always match the repository.
resource "aws_s3_object" "scripts" {
  for_each = fileset("${path.module}/../../scripts/container-api-ec2", "*.sh")

  bucket       = aws_s3_bucket.scripts.id
  key          = "scripts/${each.value}"
  source       = "${path.module}/../../scripts/container-api-ec2/${each.value}"
  etag         = filemd5("${path.module}/../../scripts/container-api-ec2/${each.value}")
  content_type = "text/x-shellscript"
}

# ── Host ──────────────────────────────────────────────────────────────────────

module "container_host" {
  source = "../../modules/ec2-container-host"

  name       = local.name
  region     = var.region
  account_id = local.account_id

  vpc_id = module.vpc.vpc_id
  # The public tier: reachable from the internet, and reachable by Let's Encrypt.
  subnet_id = module.vpc.public_subnet_ids[0]

  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  public_key        = var.ssh_public_key
  allowed_ssh_cidrs = var.allowed_ssh_cidrs

  ecr_repository_arn = module.ecr.repository_arn
  scripts_bucket_arn = aws_s3_bucket.scripts.arn
  parameter_path     = local.parameter_path

  dynamodb_table_arns = [module.dynamodb.table_arn, "${module.dynamodb.table_arn}/index/*"]

  user_data_base64 = base64encode(templatefile(
    "${path.module}/../../user-data/container-api-ec2/bootstrap.sh",
    {
      project        = var.project
      region         = var.region
      scripts_bucket = aws_s3_bucket.scripts.id
      parameter_path = local.parameter_path
    }
  ))

  # The scripts must exist in the bucket before the host boots and downloads
  # them.
  depends_on = [aws_s3_object.scripts]
}

# ── Cache ─────────────────────────────────────────────────────────────────────
#
# Off by default, because it is the only part of this stack with a meaningful
# fixed cost: serverless Valkey bills a minimum storage footprint whether or not
# anything uses it. With a single instance the rate limiter's in-process
# counters are correct, so the cache only becomes necessary with a second one.

module "valkey" {
  source = "../../modules/valkey-cache"
  count  = var.enable_cache ? 1 : 0

  name          = "${var.project}-cache"
  description   = "Rate limiter counters for ${var.project}"
  iam_user_name = "${var.project}-cache-iam"
  key_prefix    = var.cache_key_prefix

  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr_block
  subnet_ids     = module.vpc.private_subnet_ids

  client_security_group_ids = [module.container_host.security_group_id]

  max_storage_gb      = var.cache_max_storage_gb
  max_ecpu_per_second = var.cache_max_ecpu_per_second
}

data "aws_iam_policy_document" "cache_connect" {
  count = var.enable_cache ? 1 : 0

  statement {
    sid     = "ConnectToValkey"
    actions = ["elasticache:Connect"]

    resources = [
      "arn:aws:elasticache:${var.region}:${local.account_id}:serverlesscache:${module.valkey[0].cache_name}",
      "arn:aws:elasticache:${var.region}:${local.account_id}:user:${module.valkey[0].iam_user_name}",
    ]
  }
}

resource "aws_iam_role_policy" "cache_connect" {
  count = var.enable_cache ? 1 : 0

  name   = "${var.project}-cache-connect"
  role   = module.container_host.role_name
  policy = data.aws_iam_policy_document.cache_connect[0].json
}

# ── Application configuration ─────────────────────────────────────────────────
#
# Written to Parameter Store, which deploy.sh materialises into the container's
# environment. Values the infrastructure already knows are published here so
# nobody copies them by hand; secrets are published separately with add-keys.sh
# and never pass through Terraform state.

resource "aws_ssm_parameter" "table_name" {
  name  = "${local.parameter_path}/DYNAMODB_TABLE_NAME"
  type  = "String"
  value = module.dynamodb.table_name
}

resource "aws_ssm_parameter" "region" {
  name  = "${local.parameter_path}/AWS_REGION"
  type  = "String"
  value = var.region
}

resource "aws_ssm_parameter" "trust_proxy_hops" {
  name        = "${local.parameter_path}/TRUST_PROXY_HOPS"
  description = "nginx sits in front of the container, so exactly one hop is trusted"
  type        = "String"
  value       = "1"
}

resource "aws_ssm_parameter" "redis_host" {
  count = var.enable_cache ? 1 : 0

  name  = "${local.parameter_path}/REDIS_HOST"
  type  = "String"
  value = module.valkey[0].endpoint_address
}

resource "aws_ssm_parameter" "redis_port" {
  count = var.enable_cache ? 1 : 0

  name  = "${local.parameter_path}/REDIS_PORT"
  type  = "String"
  value = tostring(module.valkey[0].endpoint_port)
}

resource "aws_ssm_parameter" "redis_user" {
  count = var.enable_cache ? 1 : 0

  name  = "${local.parameter_path}/REDIS_USERNAME"
  type  = "String"
  value = module.valkey[0].iam_user_name
}

resource "aws_ssm_parameter" "redis_tls" {
  count = var.enable_cache ? 1 : 0

  name        = "${local.parameter_path}/REDIS_TLS"
  description = "IAM authentication requires TLS"
  type        = "String"
  value       = "true"
}
