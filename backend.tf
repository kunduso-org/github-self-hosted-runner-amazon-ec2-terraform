terraform {
  backend "s3" {
    bucket  = "kunduso-terraform-state-us-west-2"
    encrypt = true
    key     = "tf/github-self-hosted-runner-amazon-ec2-terraform/terraform.tfstate"
    region  = "us-west-2"
  }
}