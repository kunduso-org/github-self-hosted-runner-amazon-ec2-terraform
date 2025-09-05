#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key
resource "aws_kms_key" "encrypt_ssm" {
  enable_key_rotation     = true
  description             = "Key to encrypt the ssm resource in ${var.name}."
  deletion_window_in_days = 7
}
#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias
resource "aws_kms_alias" "encrypt_ssm" {
  name          = "alias/${var.name}-encrypt-ssm"
  target_key_id = aws_kms_key.encrypt_ssm.key_id
}
data "aws_iam_policy_document" "encrypt_ssm" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["${local.principal_root_arn}"]
    }
    actions   = ["kms:*"]
    resources = [aws_kms_key.encrypt_ssm.arn]
  }

  statement {
    sid    = "Allow SSM Service"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncrypt*"
    ]
    resources = [aws_kms_key.encrypt_ssm.arn]
  }
}


#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy
resource "aws_kms_key_policy" "encrypt_ssm" {
  key_id = aws_kms_key.encrypt_ssm.id
  policy = data.aws_iam_policy_document.encrypt_ssm.json
}

resource "aws_ssm_parameter" "nat_gateway_public_ips" {
  name   = "/github-self-hosted-runner-ip-address"
  type   = "SecureString"
  value  = join(",", [for nat in module.vpc.nat_gateway : nat.public_ip])
  key_id = aws_kms_key.encrypt_ssm.arn

  tags = {
    Name = "${var.name}-ip-addresses"
  }
}

resource "aws_ssm_parameter" "deregistration_script" {
  name = "/${var.name}/deregistration-script"
  type = "SecureString"
  value = templatefile("${path.module}/scripts/deregister-runner.sh", {
    secret_name         = aws_secretsmanager_secret.github_runner_credentials.name
    region              = var.region
    github_organization = var.github_organization
  })
  key_id = aws_kms_key.encrypt_ssm.arn
  tags = {
    Name = "${var.name}-deregistration-script"
  }
}