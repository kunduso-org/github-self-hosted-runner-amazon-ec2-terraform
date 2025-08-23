data "aws_iam_policy_document" "ssm_kms" {
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
    resources = ["*"]
  }
}

resource "aws_kms_key" "ssm_parameters" {
  description             = "KMS key for SSM parameter encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.ssm_kms.json
}

resource "aws_kms_alias" "ssm_parameters" {
  name          = "alias/${var.name}-ssm"
  target_key_id = aws_kms_key.ssm_parameters.key_id
}

resource "aws_ssm_parameter" "nat_gateway_public_ips" {
  name   = "/github-self-hosted-runner-ip-address"
  type   = "StringList"
  value  = join(",", [for nat in module.vpc.nat_gateway : nat.public_ip])
  key_id = aws_kms_key.ssm_parameters.arn

  tags = {
    Name = "${var.name}-ip-addresses"
  }
}

resource "aws_ssm_parameter" "deregistration_script" {
  name   = "/${var.name}/deregistration-script"
  type   = "SecureString"
  value  = file("${path.module}/scripts/deregister-runner.sh")
  key_id = aws_kms_key.ssm_parameters.arn

  tags = {
    Name = "${var.name}-deregistration-script"
  }
}