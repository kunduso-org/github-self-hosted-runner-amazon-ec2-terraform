data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_iam_role" "github_runner" {
  name = "${var.name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "github_runner" {
  name = "${var.name}-ec2-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.github_runner_secrets.arn
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = aws_efs_file_system.github_runner_work.arn
      }
    ]
  })
}

# Add Session Manager permissions
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.github_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "github_runner" {
  role       = aws_iam_role.github_runner.name
  policy_arn = aws_iam_policy.github_runner.arn
}

resource "aws_iam_instance_profile" "github_runner" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.github_runner.name
}

resource "aws_security_group" "github_runner" {
  name        = "${var.name}-sg"
  description = "Security group for GitHub self-hosted runners"
  vpc_id      = module.vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sg"
  }
}

resource "aws_launch_template" "github_runner" {
  name_prefix   = var.name
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.runner_instance_type

  vpc_security_group_ids = [aws_security_group.github_runner.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 1
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.github_runner.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    secret_name         = aws_secretsmanager_secret.github_runner_credentials.name
    region              = var.region
    github_organization = var.github_organization
    efs_dns_name        = aws_efs_file_system.github_runner_work.dns_name
    log_group_name      = aws_cloudwatch_log_group.github_runner.name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}"
    }
  }
}

resource "aws_autoscaling_group" "github_runner" {
  name                      = "${var.name}-asg"
  vpc_zone_identifier       = module.vpc.private_subnets.*.id
  target_group_arns         = []
  health_check_type         = "EC2"
  health_check_grace_period = 300

  min_size         = var.runner_min_size
  max_size         = var.runner_max_size
  desired_capacity = var.runner_desired_capacity

  launch_template {
    id      = aws_launch_template.github_runner.id
    version = aws_launch_template.github_runner.latest_version
  }
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
      skip_matching          = true
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-asg"
    propagate_at_launch = false
  }
}