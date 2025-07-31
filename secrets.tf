
resource "aws_kms_key" "github_runner_secrets" {
  description             = "KMS key for GitHub runner secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "github_runner_secrets" {
  name          = "alias/${var.name}-secret"
  target_key_id = aws_kms_key.github_runner_secrets.key_id
}
#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy
resource "aws_kms_key_policy" "encrypt_secret" {
  key_id = aws_kms_key.github_runner_secrets.id
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
            "kms:EncryptionContext:SecretARN" : [local.secret_arn]
          }
        }
      }
    ]
    Version = "2012-10-17"
  })
}

resource "aws_secretsmanager_secret" "github_runner_credentials" {
  name                    = "${var.name}-credentials-v2"
  description             = "GitHub App credentials for self-hosted runners"
  kms_key_id              = aws_kms_key.github_runner_secrets.arn
  recovery_window_in_days = 0
  #checkov:skip=CKV2_AWS_57: Ensure Secrets Manager secrets should have automatic rotation enabled
  #reason: These values are managed by GitHub.
}

resource "aws_secretsmanager_secret_version" "github_runner_credentials" {
  secret_id = aws_secretsmanager_secret.github_runner_credentials.id
  secret_string = jsonencode({
    app_id          = var.github_app_id
    installation_id = var.github_installation_id
    private_key     = var.github_private_key
  })
}