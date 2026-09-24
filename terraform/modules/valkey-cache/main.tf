# ─────────────────────────────────────────────────────────────────────────────
# VALKEY SERVERLESS (ElastiCache) with IAM authentication.
#
# Backs the distributed rate limiter. Lives in the private tier, which has no
# route to an internet gateway, so the only way in is from a security group
# explicitly allowed below.
#
# IAM auth means there is no password anywhere: not in Terraform state, not in
# Parameter Store, not in an environment variable. The client exchanges its
# instance role for a short-lived token on every connection. IAM auth requires
# TLS, which serverless enables by default.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "cache" {
  name        = "${var.name}-sg"
  description = "Valkey serverless, reachable only from allowed client groups"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# Access is granted by security group rather than by CIDR: an address range
# outlives the instance that held it, a group membership does not.
resource "aws_vpc_security_group_ingress_rule" "clients" {
  count = length(var.client_security_group_ids)

  security_group_id            = aws_security_group.cache.id
  description                  = "Valkey from an allowed client"
  ip_protocol                  = "tcp"
  from_port                    = var.cache_port
  to_port                      = var.cache_port
  referenced_security_group_id = var.client_security_group_ids[count.index]
}

# A cache answers; it does not initiate. Egress is restricted to the VPC rather
# than left open, so a compromised node has no outbound path at all — which,
# combined with the private tier having no internet route, means two independent
# controls would have to fail before data could leave this way.
resource "aws_vpc_security_group_egress_rule" "vpc_only" {
  security_group_id = aws_security_group.cache.id
  description       = "Replies within the VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr_block
}

# The user group requires a user named "default", but nobody connects as it.
# Turned off with no permissions. Valkey does not accept
# "no-password-required", so it carries a password that is never used and never
# leaves Terraform state.
resource "random_password" "default_user" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}"
}

resource "aws_elasticache_user" "default" {
  user_id       = "${var.name}-default"
  user_name     = "default"
  engine        = "valkey"
  access_string = "off -@all"

  authentication_mode {
    type      = "password"
    passwords = [random_password.default_user.result]
  }
}

# For IAM authentication user_id and user_name must be identical.
#
# The access string is scoped rather than "~* +@all". This identity exists to
# count requests: it can read and write keys under the rate limiter's prefix and
# run the Lua script that makes the increment atomic, and it can do nothing
# else. If the application is compromised, the blast radius on this cache is one
# key prefix.
resource "aws_elasticache_user" "iam" {
  user_id       = var.iam_user_name
  user_name     = var.iam_user_name
  engine        = "valkey"
  access_string = "on ~${var.key_prefix}* +@read +@write +@scripting"

  authentication_mode {
    type = "iam"
  }
}

resource "aws_elasticache_user_group" "this" {
  user_group_id = "${var.name}-ug"
  engine        = "valkey"

  user_ids = [
    aws_elasticache_user.default.user_id,
    aws_elasticache_user.iam.user_id,
  ]
}

resource "aws_elasticache_serverless_cache" "this" {
  name                 = var.name
  engine               = "valkey"
  major_engine_version = var.major_engine_version
  description          = var.description

  security_group_ids = [aws_security_group.cache.id]
  subnet_ids         = var.subnet_ids
  user_group_id      = aws_elasticache_user_group.this.id

  # Serverless bills by stored data and by compute units, both of which scale
  # with use and neither of which has a ceiling by default. A rate limiter holds
  # a handful of short-lived counters, so a low cap costs nothing in practice and
  # turns a runaway key leak — or an attacker deliberately inflating the key
  # space — into throttling instead of an unbounded bill.
  cache_usage_limits {
    data_storage {
      maximum = var.max_storage_gb
      unit    = "GB"
    }

    ecpu_per_second {
      maximum = var.max_ecpu_per_second
    }
  }

  tags = var.tags
}
