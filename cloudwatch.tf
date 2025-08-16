#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key
resource "aws_kms_key" "cloudwatch_kms_key" {
  description             = "KMS key for github runner"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}
#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias
resource "aws_kms_alias" "key" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.cloudwatch_kms_key.id
}
#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy
resource "aws_kms_key_policy" "encrypt_cloudwatch" {
  key_id = aws_kms_key.cloudwatch_kms_key.id
  policy = jsonencode({
    Id = "encryption-rest"
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "${local.principal_root_arn}"
        }
        Resource = "*"
        Sid      = "Enable IAM User Permissions"
      },
      {
        Effect : "Allow",
        Principal : {
          Service : "${local.principal_logs_arn}"
        },
        Action : [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ],
        Resource : "*",
        Condition : {
          ArnEquals : {
            "kms:EncryptionContext:aws:logs:arn" : [
              local.gh_runner_lifecycle_log_group_arn
            ]
          }
        }
      }
    ]
    Version = "2012-10-17"
  })
}

resource "aws_cloudwatch_log_group" "github_runner_lifecycle" {
  name              = "/github-runner/${var.name}/lifecycle"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudwatch_kms_key.arn
  tags = {
    Name = "${var.name}-lifecycle-logs"
  }
  depends_on = [aws_kms_key.cloudwatch_kms_key]
}

# Add permissions to IAM role
resource "aws_iam_policy" "cloudwatch_logs" {
  name = "${var.name}-cloudwatch-logs-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.github_runner_lifecycle.arn}",
          "${aws_cloudwatch_log_group.github_runner_lifecycle.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.cloudwatch_kms_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.github_runner.name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}