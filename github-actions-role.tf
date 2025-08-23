# GitHub Actions runner role for infrastructure provisioning
resource "aws_iam_role" "github_actions_runner" {
  name                 = "${var.name}-github-actions-runner-role"
  max_session_duration = 3600 # 60 minutes, shortest possible session

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.github_runner.arn
        }
        Action = "sts:AssumeRole"

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

resource "aws_iam_role_policy_attachment" "github_actions_state" {
  role       = aws_iam_role.github_actions_runner.name
  policy_arn = aws_iam_policy.github_actions_state.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}