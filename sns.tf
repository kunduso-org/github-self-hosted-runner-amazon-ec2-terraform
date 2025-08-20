

# SNS topic for lifecycle notifications
resource "aws_sns_topic" "runner_lifecycle" {
  name              = "${var.name}-lifecycle"
  kms_master_key_id = aws_kms_key.encrypt_sns.id
}

resource "aws_kms_alias" "encrypt_sns" {
  name          = "alias/${var.name}-encrypt-sns"
  target_key_id = aws_kms_key.encrypt_sns.key_id
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

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow services to use the key"
        Effect = "Allow"
        Principal = {
          Service = [
            "sns.amazonaws.com",
            "autoscaling.amazonaws.com",
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}