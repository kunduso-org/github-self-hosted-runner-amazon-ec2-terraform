# Get current AWS account ID
data "aws_caller_identity" "current" {}

# GitHub Actions runner role for infrastructure provisioning
resource "aws_iam_role" "github_actions_runner" {
  name = "${var.name}-github-actions-runner-role"
  max_session_duration = 1800  # 30 minutes
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.github_runner.arn
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region,
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          },
          StringLike = {
            "aws:userid" = "${aws_iam_role.github_runner.unique_id}:*"
          }
        }
      }
    ]
  })
}

# State management permissions for GitHub Actions
resource "aws_iam_policy" "github_actions_state" {
  name = "${var.name}-github-actions-state-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::kunduso-terraform-state-us-west-2",
          "arn:aws:s3:::kunduso-terraform-state-us-west-2/*"
        ]
      }
    ]
  })
}

# Core permissions for GitHub Actions infrastructure management
resource "aws_iam_policy" "github_actions_core" {
  name = "${var.name}-github-actions-core-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "vpc:*",
          "iam:*",
          "s3:*",
          "kms:*",
          "logs:*",
          "secretsmanager:*",
          "ssm:*",
          "autoscaling:*",
          "elasticfilesystem:*",
          "sts:GetCallerIdentity",
          "sts:AssumeRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_state" {
  role       = aws_iam_role.github_actions_runner.name
  policy_arn = aws_iam_policy.github_actions_state.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_core" {
  role       = aws_iam_role.github_actions_runner.name
  policy_arn = aws_iam_policy.github_actions_core.arn
}