resource "aws_ssm_parameter" "nat_gateway_public_ips" {
  name  = "/github-self-hosted-runner-ip-address"
  type  = "StringList"
  value = join(",", [for nat in module.vpc.nat_gateway : nat.public_ip])

  tags = {
    Name = "${var.name}-ip-addresses"
  }
}