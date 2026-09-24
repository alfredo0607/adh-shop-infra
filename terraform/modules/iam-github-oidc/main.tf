# Lets GitHub Actions assume a role in this account without a stored secret.
#
# The alternative is an access key pair in repository secrets. That key is
# long-lived, valid from anywhere, and invisible once leaked — a fork, a
# compromised action or a careless log exposes an AWS credential that keeps
# working until somebody notices and rotates it.
#
# With OIDC, GitHub signs a short-lived token describing exactly which
# repository and which ref is running, AWS verifies that signature, and the
# condition below decides whether to trust it. Nothing is stored, and a token
# stolen mid-run expires in an hour.

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.thumbprints

  tags = var.tags
}

locals {
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The subject is what makes this safe. Without it, any GitHub repository in
    # the world could assume this role. Matching on repo AND ref means a pull
    # request from a fork cannot deploy, because its ref is not refs/heads/main.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.allowed_subjects
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  # An hour is longer than any deployment here takes, and shorter than a
  # working day.
  max_session_duration = 3600

  tags = var.tags
}

# Exactly what a deployment does and nothing else. This role cannot create
# infrastructure, read the state bucket, or touch another project's parameters.
data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [var.ecr_repository_arn]
  }

  # Deployment runs through Session Manager rather than SSH. No key is
  # distributed, no port is required, and every command is recorded in
  # CloudTrail against the identity that ran it.
  statement {
    sid     = "RunDeployment"
    actions = ["ssm:SendCommand"]
    resources = [
      var.instance_arn,
      "arn:${var.partition}:ssm:${var.region}::document/AWS-RunShellScript",
    ]
  }

  statement {
    sid = "ReadCommandResult"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.role_name}-deploy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.deploy.json
}
