data "aws_caller_identity" "current" {}
locals {
  principal_root_arn                = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  principal_logs_arn                = "logs.${var.region}.amazonaws.com"
  gh_runner_lifecycle_log_group_arn = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.name}/lifecycle"
  secret_arn                        = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name}-credentials-v2"
  sns_topic_arn                     = "arn:aws:sns:${var.region}:${data.aws_caller_identity.current.account_id}:${var.name}-lifecycle"
  asg_arn                           = "arn:aws:autoscaling:${var.region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${var.name}-asg"
  lambda_arn                        = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${var.name}-deregistration"
}