# Payment emails: a queue the API writes to, and a Lambda that turns each
# message into an email to the buyer.
#
# The queue is what decouples the two. The API answers the buyer as soon as the
# payment is stored and hands the email off; Gmail being slow, down or refusing
# the login never delays or fails a payment. Messages wait in the queue and are
# retried, and those that keep failing move to a dead-letter queue instead of
# being lost.

locals {
  # SQS hides a message for this long after handing it to the Lambda. It must
  # outlast the function comfortably, or a slow send is delivered twice.
  visibility_timeout_seconds = var.timeout_seconds * 6
}

# The messages carry the buyer's name, email and address: the same data the
# table holds, under the same kind of key (AWS managed). A customer managed key
# would add a charge and key policies on both sides for no protection the
# table does not already set as the bar.
#trivy:ignore:AWS-0135
resource "aws_sqs_queue" "dead_letter" {
  name                    = "${var.name}-dlq"
  sqs_managed_sse_enabled = true
  # Long enough to notice the alarm and replay them, and no longer: they hold
  # personal data.
  message_retention_seconds = 345600 # 4 days

  tags = var.tags
}

#trivy:ignore:AWS-0135
resource "aws_sqs_queue" "this" {
  name                       = var.name
  sqs_managed_sse_enabled    = true
  visibility_timeout_seconds = local.visibility_timeout_seconds
  # An email about a payment is useless a day later.
  message_retention_seconds = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = var.tags
}

resource "aws_sqs_queue_redrive_allow_policy" "dead_letter" {
  queue_url = aws_sqs_queue.dead_letter.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

# ── Function ──────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = 14

  tags = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = var.tags
}

# What the function does and nothing else: read its queue, read its two
# parameters, write its logs.
data "aws_iam_policy_document" "function" {
  statement {
    sid = "ConsumeQueue"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.this.arn]
  }

  statement {
    sid       = "ReadMailCredentials"
    actions   = ["ssm:GetParametersByPath"]
    resources = ["arn:${var.partition}:ssm:${var.region}:${var.account_id}:parameter${var.parameter_path}"]
  }

  # SecureString parameters are encrypted with the AWS managed SSM key. The
  # condition limits decrypting to calls made through Parameter Store.
  statement {
    sid       = "DecryptMailCredentials"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
}

resource "aws_iam_role_policy" "function" {
  name   = var.name
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.function.json
}

# The package is built by build.sh next to the source, then zipped here.
data "archive_file" "package" {
  type        = "zip"
  source_dir  = var.build_dir
  output_path = "${path.module}/.package/${var.name}.zip"
}

# No tracing: X-Ray would add a charge to follow one function and one SMTP call.
#trivy:ignore:AWS-0066
resource "aws_lambda_function" "this" {
  function_name = var.name
  description   = "Emails the buyer the outcome of a payment"
  role          = aws_iam_role.this.arn

  runtime       = "nodejs22.x"
  architectures = ["arm64"]
  handler       = "src/handler.handler"
  memory_size   = 256
  timeout       = var.timeout_seconds

  filename         = data.archive_file.package.output_path
  source_code_hash = data.archive_file.package.output_base64sha256

  environment {
    variables = {
      MAIL_PARAMETER_PATH = var.parameter_path
      MAIL_FROM_NAME      = var.from_name
      STOREFRONT_URL      = var.storefront_url
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  lifecycle {
    # archive_file zips whatever is in the directory. Without dependencies the
    # function deploys fine and then fails on its first import.
    precondition {
      condition     = fileexists("${var.build_dir}/node_modules/nodemailer/package.json")
      error_message = "The Lambda package has no dependencies. Run lambdas/payment-mailer/build.sh before plan or apply."
    }
  }

  depends_on = [aws_iam_role_policy.function]

  tags = var.tags
}

resource "aws_lambda_event_source_mapping" "queue" {
  event_source_arn = aws_sqs_queue.this.arn
  function_name    = aws_lambda_function.this.arn

  # One message per invocation: a failure retries exactly one email, and the
  # window for a duplicate after a crash is as small as it can be.
  batch_size              = 1
  function_response_types = ["ReportBatchItemFailures"]

  # Gmail limits how fast an account may send. Two at a time is far above this
  # store's volume and far below that limit, and unlike reserved concurrency it
  # takes nothing from the account's shared pool.
  scaling_config {
    maximum_concurrency = 2
  }
}

# ── Alarm ─────────────────────────────────────────────────────────────────────

# A message in the dead-letter queue is an email a buyer never received. The
# alarm has no action attached: it shows in the console, and wiring it to a
# notification is a line away when someone is on call.
resource "aws_cloudwatch_metric_alarm" "dead_letters" {
  alarm_name          = "${var.name}-dead-letters"
  alarm_description   = "Payment emails that failed ${var.max_receive_count} times. Inspect, fix, then redrive from the console."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dead_letter.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  tags = var.tags
}
