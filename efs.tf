resource "aws_efs_file_system" "github_runner_work" {
  creation_token = "${var.name}-work-dir"
  encrypted      = true
  
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

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.github_runner.id]
  }

  tags = {
    Name = "${var.name}-efs-sg"
  }
}