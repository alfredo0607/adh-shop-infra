# EC2 host running nginx as a TLS terminating reverse proxy in front of one or
# more Docker containers.
#
# Lives in a public subnet because it must be reachable from the internet:
# nginx answers on 80/443, and certbot's HTTP-01 challenge needs an inbound
# connection on port 80 from Let's Encrypt.

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
}

# ── Security group ────────────────────────────────────────────────────────────
#
# Only the ports nginx serves are open to the internet. The application ports
# are deliberately absent.
#
# Exposing a container port publicly would let anyone who knows the address
# reach the application directly on plain HTTP, bypassing nginx, the TLS
# certificate and the 80-to-443 redirect entirely — which makes all of the
# certbot work optional for an attacker. Containers publish to 127.0.0.1 only
# and are reachable exclusively through the proxy.

resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Container host: public HTTP/HTTPS, administrative SSH"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.this.id
  description       = "HTTP. Serves the ACME challenge and redirects to HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# SSH, opened to whatever the caller asks for — including the whole internet.
#
# The scanner is right to flag that, and the rule is a good one: AWS-0107
# targets remote administration ports specifically, which is why 80 and 443 pass
# untouched while 22 does not. An open SSH port collects credential-stuffing
# traffic from the moment the address is reachable.
#
# It is accepted here because the operator asked for it, and because the module
# is not the right place to overrule that. The narrower options remain a single
# line away: allowed_ssh_cidrs = ["x.x.x.x/32"] restricts it to one address, and
# an empty list removes the rule entirely while leaving Session Manager working,
# since that needs no inbound rule at all.
#
# Recorded here rather than suppressed in a config file, so the next reader sees
# the reasoning next to the decision.
#trivy:ignore:AWS-0107
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count = length(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "Administrative SSH"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.allowed_ssh_cidrs[count.index]
}

# Egress is restricted by port rather than left wide open.
#
# The destination cannot be narrowed: the host has to reach ECR, the Let's
# Encrypt CDN and the distribution's package mirrors, none of which publish a
# stable address range worth pinning. What can be narrowed is the protocol, and
# limiting it to DNS, HTTP and HTTPS removes every other outbound path — which
# is what a compromised container would reach for to open a reverse shell or
# exfiltrate over an unusual port.
#
# Trivy flags the 0.0.0.0/0 destination regardless of port. That is accurate and
# accepted: a host that installs packages and renews certificates needs the
# open internet. Narrowing the ports is the part that was actually available.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "ECR, AWS APIs, ACME, package mirrors"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.this.id
  description       = "Package mirrors and OCSP responders that still use plain HTTP"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.this.id
  description       = "DNS"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}

#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.this.id
  description       = "DNS over TCP, for responses that exceed the UDP limit"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}

# ── Instance role ─────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "permissions" {
  # Pulling images. GetAuthorizationToken cannot be scoped to a repository;
  # everything else is.
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.ecr_repository_arn]
  }

  # Application configuration and secrets. Scoped to this project's parameter
  # path, so a compromised host cannot read another service's credentials.
  statement {
    sid = "ReadOwnParameters"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = ["arn:aws:ssm:${var.region}:${var.account_id}:parameter${var.parameter_path}/*"]
  }

  statement {
    sid       = "DecryptOwnParameters"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }

  # Management scripts, read only. The host never writes to this bucket.
  statement {
    sid       = "ReadScripts"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.scripts_bucket_arn, "${var.scripts_bucket_arn}/*"]
  }

  # Data plane only. The host cannot create, alter or delete a table, so a
  # compromised application cannot destroy the data it serves.
  dynamic "statement" {
    for_each = length(var.dynamodb_table_arns) > 0 ? [1] : []

    content {
      sid = "DynamoDbDataPlane"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:BatchGetItem",
        "dynamodb:Query",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:TransactGetItems",
        "dynamodb:TransactWriteItems",
        "dynamodb:ConditionCheckItem",
      ]
      resources = var.dynamodb_table_arns
    }
  }

  # add-keys.sh publishes key material pulled from the scripts bucket. Write is
  # scoped to this project's parameter path, so a compromised host cannot
  # overwrite another service's configuration.
  statement {
    sid = "PublishOwnParameters"
    actions = [
      "ssm:PutParameter",
      "ssm:AddTagsToResource",
    ]
    resources = ["arn:aws:ssm:${var.region}:${var.account_id}:parameter${var.parameter_path}/*"]
  }

  statement {
    sid       = "EncryptOwnParameters"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }

  statement {
    sid = "WriteLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/${var.name}*"]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.name}-policy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

# Lets an operator open a shell through Session Manager instead of SSH. Useful
# enough on its own, but the real value is that it makes closing port 22
# entirely a viable option later.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-profile"
  role = aws_iam_role.this.name

  tags = var.tags
}

# ── Instance ──────────────────────────────────────────────────────────────────

resource "aws_instance" "this" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  key_name               = var.key_pair_name

  user_data_base64 = var.user_data_base64
  # Changing user data rebuilds the host rather than leaving it in a state that
  # no longer matches the script that supposedly produced it.
  user_data_replace_on_change = true

  # IMDSv2 required. With IMDSv1 still enabled, a single server-side request
  # forgery in the application is enough to read the instance role's temporary
  # credentials; the session-token handshake IMDSv2 requires cannot be
  # performed through a naive proxied request.
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true

    tags = merge(var.tags, { Name = "${var.name}-root" })
  }

  monitoring = true

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    ignore_changes = [ami]
  }
}

# A stop/start would otherwise change the public address, which breaks the DNS
# record the certificate is issued against and every client using it.
resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-eip" })
}
