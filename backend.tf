terraform {
  backend "s3" {
    bucket  = "kunduso-terraform-remote-bucket"
    encrypt = true
    key     = "tf/github-self-hosted-runner-amazon-ec2-terraform/terraform.tfstate"
    region  = "us-east-2"
  }
}