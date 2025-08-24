
# SNS topic for lifecycle notifications
resource "aws_sns_topic" "runner_lifecycle" {
  name              = "${var.name}-lifecycle"
  kms_master_key_id = aws_kms_key.encrypt_sns.id
}

# SNS subscription to Lambda
resource "aws_sns_topic_subscription" "runner_lifecycle" {
  topic_arn = aws_sns_topic.runner_lifecycle.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.runner_deregistration.arn
}

# Lambda permission for SNS
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.runner_deregistration.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.runner_lifecycle.arn
}

# KMS key for SNS encryption
resource "aws_kms_key" "encrypt_sns" {
  enable_key_rotation     = true
  description             = "Key to encrypt SNS topic in ${var.name}."
  deletion_window_in_days = 7
}

data "aws_iam_policy_document" "encrypt_sns" {
  statement {
    sid    = "Enable full access for root account"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["${local.principal_root_arn}"]
    }
    actions   = ["kms:*"]
    resources = [aws_kms_key.encrypt_sns.arn]
  }

  statement {
    sid    = "Allow AWS services"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "sns.amazonaws.com"
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.encrypt_sns.arn]
  }
}

resource "aws_kms_key_policy" "encrypt_sns" {
  key_id = aws_kms_key.encrypt_sns.id
  policy = data.aws_iam_policy_document.encrypt_sns.json
}

resource "aws_kms_alias" "encrypt_sns" {
  name          = "alias/${var.name}-encrypt-sns"
  target_key_id = aws_kms_key.encrypt_sns.key_id
}