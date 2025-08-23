# KMS key for EFS encryption
resource "aws_kms_key" "encrypt_efs" {
  enable_key_rotation     = true
  description             = "Key to encrypt EFS file system in ${var.name}."
  deletion_window_in_days = 7
}

data "aws_iam_policy_document" "encrypt_efs" {
  statement {
    sid    = "Enable full access for root account"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["${local.principal_root_arn}"]
    }
    actions   = ["kms:*"]
    resources = [aws_kms_key.encrypt_efs.arn]
  }

  statement {
    sid    = "Allow EFS service"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "elasticfilesystem.amazonaws.com"
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.encrypt_efs.arn]
  }
}

resource "aws_kms_key_policy" "encrypt_efs" {
  key_id = aws_kms_key.encrypt_efs.id
  policy = data.aws_iam_policy_document.encrypt_efs.json
}

resource "aws_kms_alias" "encrypt_efs" {
  name          = "alias/${var.name}-encrypt-efs"
  target_key_id = aws_kms_key.encrypt_efs.key_id
}

resource "aws_efs_file_system" "github_runner_work" {
  creation_token = "${var.name}-work-dir"
  encrypted      = true
  kms_key_id     = aws_kms_key.encrypt_efs.arn
  tags = {
    Name = "${var.name}-work-dir"
  }
}

resource "aws_efs_mount_target" "github_runner_work" {
  count           = length(module.vpc.private_subnets)
  file_system_id  = aws_efs_file_system.github_runner_work.id
  subnet_id       = module.vpc.private_subnets[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs-sg"
  description = "Allow NFS traffic from runner instances"
  vpc_id      = module.vpc.vpc.id

  tags = {
    Name = "${var.name}-efs-sg"
  }
}

resource "aws_security_group_rule" "efs_ingress" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  description              = "Allow NFS traffic from GitHub runner instances"
  source_security_group_id = aws_security_group.github_runner.id
  security_group_id        = aws_security_group.efs.id
}