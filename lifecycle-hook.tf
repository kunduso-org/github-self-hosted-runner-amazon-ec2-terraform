# Auto Scaling lifecycle hook for termination
resource "aws_autoscaling_lifecycle_hook" "runner_termination" {
  name                    = "${var.name}-termination-hook"
  autoscaling_group_name  = aws_autoscaling_group.github_runner.name
  default_result          = "ABANDON"
  heartbeat_timeout       = 300 # 5 minutes
  lifecycle_transition    = "autoscaling:EC2_INSTANCE_TERMINATING"
  notification_target_arn = aws_sns_topic.runner_lifecycle.arn
  role_arn                = aws_iam_role.lifecycle_hook.arn
}

# SNS topic for lifecycle notifications
resource "aws_sns_topic" "runner_lifecycle" {
  name = "${var.name}-lifecycle"
}

# Lambda function for runner deregistration
resource "aws_lambda_function" "runner_deregistration" {
  filename      = "runner_deregistration.zip"
  function_name = "${var.name}-deregistration"
  role          = aws_iam_role.lambda_deregistration.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 60
reserved_concurrent_executions = 5
  environment {
    variables = {
      SECRET_NAME         = aws_secretsmanager_secret.github_runner_credentials.name
      REGION              = var.region
      GITHUB_ORGANIZATION = var.github_organization
      LIFECYCLE_LOG_GROUP = aws_cloudwatch_log_group.github_runner_lifecycle.name
    }
  }
    vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }
  layers = [aws_lambda_layer_version.lambda_layer_pyjwt.arn]
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  depends_on = [data.archive_file.lambda_zip]
}

# Lambda deployment package (code only, dependencies in layer)
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "runner_deregistration.zip"
  source {
    content  = file("${path.module}/lambda_package/lambda_deregistration.py")
    filename = "index.py"
  }
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

# IAM role for lifecycle hook
resource "aws_iam_role" "lifecycle_hook" {
  name = "${var.name}-lifecycle-hook-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "autoscaling.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for lifecycle hook
resource "aws_iam_role_policy" "lifecycle_hook" {
  name = "${var.name}-lifecycle-hook-policy"
  role = aws_iam_role.lifecycle_hook.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.runner_lifecycle.arn
      }
    ]
  })
}

# Lambda IAM role
resource "aws_iam_role" "lambda_deregistration" {
  name = "${var.name}-lambda-deregistration-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda IAM policy
resource "aws_iam_role_policy" "lambda_deregistration" {
  name = "${var.name}-lambda-deregistration-policy"
  role = aws_iam_role.lambda_deregistration.id

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
        Resource = "arn:aws:logs:${var.region}:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.github_runner_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.github_runner_secrets.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.github_runner_lifecycle.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CompleteLifecycleAction"
        ]
        Resource = "*"
      }
    ]
  })
}