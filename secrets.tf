
data "aws_iam_policy_document" "github_runner_kms" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow GitHub Runner Role"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.github_runner.arn]
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "github_runner_secrets" {
  description             = "KMS key for GitHub runner secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.github_runner_kms.json
}

resource "aws_kms_alias" "github_runner_secrets" {
  name          = "alias/${var.name}-secret"
  target_key_id = aws_kms_key.github_runner_secrets.key_id
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