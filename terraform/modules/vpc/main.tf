# VPC with one public tier and one private tier.
#
# Public  — anything that must be reachable from the internet, or that needs
#           outbound internet access. The container host lives here: nginx has
#           to answer on 80/443, and certbot's HTTP-01 challenge requires an
#           inbound connection on port 80 from Let's Encrypt.
#
# Private — anything that must never be reachable from the internet. The Redis
#           cache lives here. It has no route to an internet gateway at all,
#           which is a stronger guarantee than a security group rule: even a
#           misconfigured group cannot expose it.
#
# There is deliberately NO NAT gateway. A NAT costs roughly 32 USD/month and is
# only needed when something in the private tier must reach the internet.
# Nothing here does: the cache does not call out, and AWS service traffic goes
# through gateway endpoints instead, which are free.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Two AZs because subnet groups for managed services require it, and because
  # a single-AZ private tier cannot be made highly available later without
  # renumbering. The second subnet costs nothing while empty.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

# ── Public tier ───────────────────────────────────────────────────────────────

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-igw" })
}

# Assigning a public address is the definition of a public subnet, which is the
# whole reason this tier exists: nginx must be reachable and certbot needs an
# inbound connection on port 80. Trivy flags it on every public subnet ever
# written; anything that must not be reachable goes in the private tier below,
# which has no route to the internet gateway at all.
#trivy:ignore:AWS-0164
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  # The container host needs a routable address for nginx and for certbot.
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private tier ──────────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-private-${count.index + 1}"
    Tier = "private"
  })
}

# No default route. Traffic leaving this table can only reach the VPC itself or
# the gateway endpoints below. That is the isolation, expressed as routing
# rather than as a firewall rule.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── Gateway endpoints ─────────────────────────────────────────────────────────
#
# Gateway endpoints are free and work by route table entry rather than by ENI.
# They keep DynamoDB and S3 traffic on the AWS network instead of sending it out
# through the internet gateway, which is both faster and one less path to
# secure. Interface endpoints would cost roughly 7 USD/month each; these do not.

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id], [aws_route_table.private.id])

  tags = merge(var.tags, { Name = "${var.name}-dynamodb-endpoint" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id], [aws_route_table.private.id])

  tags = merge(var.tags, { Name = "${var.name}-s3-endpoint" })
}

# ── Flow logs ─────────────────────────────────────────────────────────────────
#
# Without flow logs, "was this host reached from outside?" is unanswerable after
# the fact. Thirty days of retention keeps the cost negligible while covering
# the window in which an incident is usually discovered.

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = 30

  tags = var.tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "${var.name}-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.this.id
  traffic_type    = "REJECT"
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(var.tags, { Name = "${var.name}-flow-logs" })
}
