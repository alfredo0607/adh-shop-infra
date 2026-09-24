# Valkey cache backing the distributed rate limiter.
#
# A separate stack because it depends on the container host: the cache admits
# traffic from that host's security group, and grants its role permission to
# connect. Folding this into data-store would be a cycle, since the container
# stack already reads the table ARN from there.
#
# Apply order: network -> data-store -> container-api-ec2 -> cache.

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "container_api" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "container-api-ec2/terraform.tfstate"
    region = var.region
  }
}

locals {
  # Derived rather than supplied: see bootstrap/remote-state for the naming.
  state_bucket = "${var.project}-terraform-state-${data.aws_caller_identity.current.account_id}"

  cache_name    = "${var.project}-cache"
  iam_user_name = "${var.project}-cache-iam"
  account_id    = data.aws_caller_identity.current.account_id
}

module "valkey" {
  source = "../../modules/valkey-cache"

  name          = local.cache_name
  description   = "Rate limiter counters for ${var.project}"
  iam_user_name = local.iam_user_name
  key_prefix    = var.key_prefix

  vpc_id         = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr_block = data.terraform_remote_state.network.outputs.vpc_cidr_block

  # The private tier. No route to an internet gateway exists from here.
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  client_security_group_ids = [
    data.terraform_remote_state.container_api.outputs.security_group_id,
  ]

  max_storage_gb      = var.max_storage_gb
  max_ecpu_per_second = var.max_ecpu_per_second
}

# ── Permission to connect ─────────────────────────────────────────────────────
#
# Attached here, to the role the container stack already created, rather than
# granted there against a name this stack has not produced yet.
#
# The reference implementation rebuilt the cache and user names as strings in
# the consuming stack, with a comment warning that they must stay in sync. That
# is a contract kept by human memory: rename the cache and the other stack keeps
# applying cleanly while granting access to a resource that no longer exists.
# Inverting the direction means both ARNs come from the resources themselves.

data "aws_iam_policy_document" "connect" {
  statement {
    sid     = "ConnectToValkey"
    actions = ["elasticache:Connect"]

    resources = [
      "arn:aws:elasticache:${var.region}:${local.account_id}:serverlesscache:${module.valkey.cache_name}",
      "arn:aws:elasticache:${var.region}:${local.account_id}:user:${module.valkey.iam_user_name}",
    ]
  }
}

resource "aws_iam_role_policy" "connect" {
  name   = "${local.cache_name}-connect"
  role   = data.terraform_remote_state.container_api.outputs.role_name
  policy = data.aws_iam_policy_document.connect.json
}

# ── Application configuration ─────────────────────────────────────────────────
#
# Published to Parameter Store, which deploy.sh already materialises into the
# container's environment. Plain strings, not SecureString: with IAM auth there
# is no password, so none of these are secret. Storing a hostname encrypted
# would be ceremony that teaches people to ignore the distinction.

resource "aws_ssm_parameter" "host" {
  name  = "/${var.project}/VALKEY_HOST"
  type  = "String"
  value = module.valkey.endpoint_address
}

resource "aws_ssm_parameter" "port" {
  name  = "/${var.project}/VALKEY_PORT"
  type  = "String"
  value = tostring(module.valkey.endpoint_port)
}

resource "aws_ssm_parameter" "user" {
  name  = "/${var.project}/VALKEY_USER"
  type  = "String"
  value = module.valkey.iam_user_name
}

resource "aws_ssm_parameter" "cache_name" {
  name        = "/${var.project}/VALKEY_CACHE_NAME"
  description = "Signing host for the IAM auth token, which differs from the endpoint"
  type        = "String"
  value       = module.valkey.cache_name
}

resource "aws_ssm_parameter" "key_prefix" {
  name  = "/${var.project}/VALKEY_KEY_PREFIX"
  type  = "String"
  value = var.key_prefix
}
