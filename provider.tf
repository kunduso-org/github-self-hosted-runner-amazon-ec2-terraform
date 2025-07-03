terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.97.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Source = "https://github.com/github-self-hosted-runner-amazon-ec2-terraform"
    }
  }
}