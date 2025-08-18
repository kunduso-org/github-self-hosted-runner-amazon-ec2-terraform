

# SNS topic for lifecycle notifications
resource "aws_sns_topic" "runner_lifecycle" {
  name = "${var.name}-lifecycle"
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
#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key
resource "aws_kms_key" "encrypt_sns" {
  enable_key_rotation     = true
  description             = "Key to encrypt sns topic in ${var.name}."
  deletion_window_in_days = 7
}
#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias
resource "aws_kms_alias" "encrypt_sns" {
  name          = "alias/${var.name}-encrypt-sns"
  target_key_id = aws_kms_key.encrypt_sns.key_id
}
#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "encrypt_sns_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["${local.principal_root_arn}"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource"
    ]
    resources = ["*"]
  }
  
  statement {
    sid    = "Allow SNS to use the key"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [local.sns_topic_arn]
  }
  
  statement {
    sid    = "Allow Auto Scaling to publish to SNS"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["autoscaling.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
  
  statement {
    sid    = "Allow Lambda to decrypt SNS messages"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}
#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy
resource "aws_kms_key_policy" "encrypt_sns" {
  key_id = aws_kms_key.encrypt_sns.id
  policy = data.aws_iam_policy_document.encrypt_sns_policy.json
}