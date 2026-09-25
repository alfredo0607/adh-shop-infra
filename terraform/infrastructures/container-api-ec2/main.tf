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
# The image CDN is part of this stack rather than its own, because it depends
# on the API: CloudFront verifies signatures the API produces, so the signing key
# pair, the key group and the parameter the API reads it from have to be created
# together or not at all.

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
#
# Line endings are normalised here rather than trusted. .gitattributes governs
# what git stores, not what a Windows checkout puts on disk, and uploading the
# working copy verbatim shipped a carriage return into the shebang. The host
# then reports a missing interpreter whose name contains an invisible
# character, which points at nothing a reader can see in the file.
#
# Normalising during the upload makes the artifact correct regardless of the
# contributor's git configuration, rather than depending on every machine
# being set up the same way.
locals {
  scripts = {
    for name in fileset("${path.module}/../../scripts/container-api-ec2", "*.sh") :
    name => replace(
      file("${path.module}/../../scripts/container-api-ec2/${name}"),
      "\r\n",
      "\n",
    )
  }
}

resource "aws_s3_object" "scripts" {
  for_each = local.scripts

  bucket       = aws_s3_bucket.scripts.id
  key          = "scripts/${each.key}"
  content      = each.value
  etag         = md5(each.value)
  content_type = "text/x-shellscript"
}

# ── Host ──────────────────────────────────────────────────────────────────────


# ── Origin reachable only through Cloudflare ─────────────────────────────────
#
# Port 443 open to the world let callers reach nginx directly, around
# Cloudflare. The API trusts two proxy hops when it reads the client address,
# so a direct caller could put any address in X-Forwarded-For and get a fresh
# rate-limit bucket on every request, with none of Cloudflare's DDoS protection
# in the way.
#
# The ranges are read from Cloudflare on every plan rather than copied here, so
# a range they add is picked up by the next apply instead of silently refusing
# the visitors routed through it. If the list cannot be fetched, or comes back
# short, the plan fails: applying a partial list would take the site offline.
#
# IPv4 only. The host has no IPv6 address, so Cloudflare reaches it over IPv4.
data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Could not fetch Cloudflare's IP ranges (HTTP ${self.status_code})."
    }
  }
}

locals {
  cloudflare_ipv4_ranges = sort(compact([
    for line in split("\n", data.http.cloudflare_ipv4.response_body) : trimspace(line)
  ]))
}

check "cloudflare_ranges_look_complete" {
  assert {
    # Cloudflare has published between 14 and 15 IPv4 ranges for years. Far
    # fewer means the response was truncated or is not the list at all.
    condition     = length(local.cloudflare_ipv4_ranges) >= 10 && alltrue([for cidr in local.cloudflare_ipv4_ranges : can(cidrnetmask(cidr))])
    error_message = "Cloudflare's IP range list looks incomplete or malformed."
  }
}

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

  key_pair_name     = var.key_pair_name
  allowed_ssh_cidrs = var.allowed_ssh_cidrs

  # The API is only reachable through Cloudflare. Its proxy must stay on: with
  # DNS-only records, visitors would connect from their own addresses and be
  # refused here.
  https_ingress_cidrs = local.cloudflare_ipv4_ranges

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

# Lets the host reach the cache, and only the cache.
#
# Defined here rather than in either module, for the same reason as the bucket
# and key policies: the host's group is an input to the cache and the cache's
# group would be an input to the host, which is a cycle Terraform refuses to
# plan. In the stack both exist and the rule simply references them.
#
# Egress from the host is bounded by protocol — DNS, HTTP, HTTPS — because the
# hosts it reaches publish no stable ranges. This one can be bounded by
# destination: it names a security group, so a Redis connection may go to the
# cache and nowhere else. Referencing the group rather than an address also
# survives the cache being replaced.
resource "aws_vpc_security_group_egress_rule" "host_to_cache" {
  count = var.enable_cache ? 1 : 0

  security_group_id            = module.container_host.security_group_id
  description                  = "Rate limiter counters"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = module.valkey[0].security_group_id
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

# ── Private image CDN ─────────────────────────────────────────────────────────
#
# Product images are served through CloudFront and reachable only with a signed
# URL the API issues. Possessing the address is not enough: the URL has to have
# been granted, and it expires.

module "assets_kms" {
  source      = "../../modules/kms"
  alias_name  = "${var.project}-assets"
  description = "Encrypts product images for ${var.project}"
}

module "assets_bucket" {
  source      = "../../modules/s3-private-assets"
  bucket_name = "${var.project}-assets-${local.account_id}"
  kms_key_arn = module.assets_kms.key_arn
}

# The signing key pair is generated outside Terraform and never passes through
# it. Only the public half is read here; the private half is uploaded to the
# scripts bucket under keys/cloudfront/, and add-keys.sh publishes it to
# Parameter Store on the host and deletes the local copy.
#
# Generating it in Terraform would be fewer steps, but the private key would
# then live in state — a file that is read on every plan, by anyone who can run
# one, long after the moment it was needed.
#
#   openssl genrsa -out private.pem 2048
#   openssl rsa -pubout -in private.pem -out public_key.pem
#   aws s3 cp private.pem s3://<scripts bucket>/keys/cloudfront/private.pem
#   rm private.pem

module "cdn" {
  source = "../../modules/cloudfront-cdn"

  name                           = "${var.project}-assets"
  s3_bucket_regional_domain_name = module.assets_bucket.bucket_regional_domain_name
  signing_public_key_pem         = var.signing_public_key_pem != null ? var.signing_public_key_pem : file("${path.module}/public_key.pem")

  aliases             = var.cdn_aliases
  acm_certificate_arn = var.cdn_acm_certificate_arn
  price_class         = var.cdn_price_class
}

# Defined here rather than in the bucket module: the policy needs the
# distribution ARN and the distribution needs the bucket domain, so expressing
# both as module inputs would be a cycle Terraform refuses to plan.
#
# Scoped by SourceArn. Without the condition, any CloudFront distribution in any
# AWS account could read this bucket.
data "aws_iam_policy_document" "cdn_read" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${module.assets_bucket.bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cdn.distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cdn_read" {
  bucket = module.assets_bucket.bucket_id
  policy = data.aws_iam_policy_document.cdn_read.json
}

# Defined here rather than in the kms module, to break the same cycle as the
# bucket policy: the key policy needs the distribution ARN, which does not exist
# when the key is created.
resource "aws_kms_key_policy" "assets" {
  key_id = module.assets_kms.key_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudFrontViaS3"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource  = "*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = module.cdn.distribution_arn }
        }
      },
    ]
  })
}

# ── Deployment identity ───────────────────────────────────────────────────────
#
# GitHub Actions assumes a role here instead of holding an access key.
#
# A stored key pair is long-lived, valid from anywhere, and silent once leaked.
# An OIDC token describes which repository and which ref is running, expires in
# an hour, and is verified by AWS against GitHub's signature — so there is no
# secret in the repository to leak in the first place.

module "deploy_role" {
  source = "../../modules/iam-github-oidc"
  count  = var.github_repository_owner == null ? 0 : 1

  role_name = "${var.project}-github-deploy"
  region    = var.region

  # The subject GitHub actually signs, which is not the one the documentation
  # examples show.
  #
  # Tokens carry immutable identifiers rather than names:
  #   repo:owner@<owner_id>/name@<repo_id>:environment:<env>
  #
  # That is a deliberate protection. Names can be released and re-registered, so
  # a policy written against "repo:alfredo0607/adh-shop-api" would follow the
  # name to whoever claims it next; the numeric ids never move. Determined by
  # reading a denied AssumeRoleWithWebIdentity event in CloudTrail, because
  # guessing the format twice had already cost two failed deployments.
  #
  # The environment rather than the ref, because a job declaring `environment:`
  # gets a subject naming it instead of the branch. Which branch may deploy is
  # enforced by GitHub, as a deployment branch policy on the environment itself.
  allowed_subjects = [
    "repo:${var.github_repository_owner}@${var.github_owner_id}/${var.github_repository_name}@${var.github_repository_id}:environment:${var.deploy_environment}",
  ]

  ecr_repository_arn   = module.ecr.repository_arn
  instance_arn         = "arn:aws:ec2:${var.region}:${local.account_id}:instance/${module.container_host.instance_id}"
  create_oidc_provider = var.create_oidc_provider
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

# The API lives on its own domain, so the storefront is always a different
# origin and every call it makes is cross-origin. Without this list the API
# answers no preflight, and the browser refuses every request.
resource "aws_ssm_parameter" "cors_allowed_origins" {
  name  = "${local.parameter_path}/CORS_ALLOWED_ORIGINS"
  type  = "String"
  value = join(",", var.storefront_origins)
}

resource "aws_ssm_parameter" "trust_proxy_hops" {
  name = "${local.parameter_path}/TRUST_PROXY_HOPS"

  # Two proxies sit in front of the container, not one: the CDN terminates TLS
  # and appends the caller's address, then nginx appends the CDN edge. Express
  # discards exactly this many entries from the right of X-Forwarded-For, so
  # trusting a single hop stops at the edge address — which rotates between
  # requests and is shared by unrelated callers. The rate limiter then buckets
  # by edge instead of by client: one caller rotating through edges gets a
  # multiple of the quota, while strangers who happen to share an edge share a
  # counter. Both failures are silent.
  #
  # Counting both hops stays forgery-resistant. A caller that sends its own
  # X-Forwarded-For has that value pushed further left by the two appends, so
  # it can never occupy the position this count selects.
  description = "the CDN edge and nginx both sit in front of the container"
  type        = "String"
  value       = "2"
}

# The API needs three things to sign a URL: the host to sign against, the key
# pair id CloudFront matches the signature to, and the private key itself. Only
# the last is a secret.
resource "aws_ssm_parameter" "cdn_domain" {
  name  = "${local.parameter_path}/CDN_DOMAIN"
  type  = "String"
  value = module.cdn.domain_name
}

resource "aws_ssm_parameter" "cdn_key_pair_id" {
  name  = "${local.parameter_path}/CDN_KEY_PAIR_ID"
  type  = "String"
  value = module.cdn.key_pair_id
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

# The token is signed against the cache NAME, not its endpoint hostname. They
# differ — the endpoint carries a generated suffix — and signing against the
# wrong one produces a token the server rejects as invalid rather than as
# unauthorised, which is a confusing place to start debugging.
resource "aws_ssm_parameter" "redis_cache_name" {
  count = var.enable_cache ? 1 : 0

  name  = "${local.parameter_path}/REDIS_CACHE_NAME"
  type  = "String"
  value = module.valkey[0].cache_name
}

resource "aws_ssm_parameter" "redis_tls" {
  count = var.enable_cache ? 1 : 0

  name        = "${local.parameter_path}/REDIS_TLS"
  description = "IAM authentication requires TLS"
  type        = "String"
  value       = "true"
}
