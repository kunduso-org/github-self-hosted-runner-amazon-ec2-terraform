data "aws_caller_identity" "current" {}

resource "aws_kms_key" "github_runner_secrets" {
  description             = "KMS key for GitHub runner secrets encryption"
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
        Sid    = "Allow GitHub Runner Role"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.github_runner.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "github_runner_secrets" {
  name          = "alias/${var.name}-secrets"
  target_key_id = aws_kms_key.github_runner_secrets.key_id
}

resource "aws_secretsmanager_secret" "github_runner_credentials" {
  name        = "${var.name}-credentials"
  description = "GitHub App credentials for self-hosted runners"
  kms_key_id  = aws_kms_key.github_runner_secrets.arn
}

resource "aws_secretsmanager_secret_version" "github_runner_credentials" {
  secret_id = aws_secretsmanager_secret.github_runner_credentials.id
  secret_string = jsonencode({
    app_id          = var.github_app_id
    installation_id = var.github_installation_id
    private_key     = var.github_private_key
  })
}