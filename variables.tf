variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "github-self-hosted-runner"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.20.20.0/26"
}

variable "subnet_cidr_public" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.20.20.0/28", "10.20.20.16/28"]
}

variable "subnet_cidr_private" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.20.20.32/28", "10.20.20.48/28"]
}

variable "github_app_id" {
  description = "GitHub App ID"
  type        = string
  sensitive   = true
}

variable "github_installation_id" {
  description = "GitHub App Installation ID"
  type        = string
  sensitive   = true
}

variable "github_private_key" {
  description = "GitHub App Private Key (PEM format)"
  type        = string
  sensitive   = true
}

variable "runner_instance_type" {
  description = "EC2 instance type for GitHub runners"
  type        = string
  default     = "t3.medium"
}

variable "runner_min_size" {
  description = "Minimum number of runners"
  type        = number
  default     = 1
}

variable "runner_max_size" {
  description = "Maximum number of runners"
  type        = number
  default     = 3
}

variable "runner_desired_capacity" {
  description = "Desired number of runners"
  type        = number
  default     = 2
}

variable "github_username" {
  description = "GitHub username for account-level runners"
  type        = string
  default     = "kunduso"
}