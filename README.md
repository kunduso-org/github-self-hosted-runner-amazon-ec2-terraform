[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-white.svg)](https://choosealicense.com/licenses/unlicense/) [![GitHub pull-requests closed](https://img.shields.io/github/issues-pr-closed/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform)](https://github.com/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform/pulls?q=is%3Apr+is%3Aclosed) [![GitHub pull-requests](https://img.shields.io/github/issues-pr/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform)](https://GitHub.com/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform/pull/) 
[![GitHub issues-closed](https://img.shields.io/github/issues-closed/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform)](https://github.com/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform/issues?q=is%3Aissue+is%3Aclosed) [![GitHub issues](https://img.shields.io/github/issues/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform)](https://GitHub.com/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform/issues/) 
[![terraform-infra-provisioning](https://github.com/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform/actions/workflows/terraform.yml/badge.svg?branch=main)](https://github.com/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform/actions/workflows/terraform.yml) [![checkov-scan](https://github.com/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform/actions/workflows/code-scan.yml/badge.svg?branch=main)](https://github.com/kunduso-org/github-self-hosted-runner-amazon-ec2-terraform/actions/workflows/code-scan.yml)

# GitHub Self-Hosted Runner on Amazon EC2 with Terraform

This repository contains Terraform infrastructure code to deploy scalable, self-hosted GitHub Actions runners on Amazon EC2 instances. The solution provides automated runner provisioning, lifecycle management, and secure deregistration using AWS Auto Scaling Groups, Lambda functions, and CloudWatch logging.

## Features

- **High Availability**: Maintains consistent runner capacity using AWS Auto Scaling Groups with automatic instance replacement across multiple Availability Zones
- **Secure Authentication**: Uses GitHub App authentication for secure API access
- **Automated Lifecycle Management**: Automatic runner registration and deregistration with dual mechanisms (Lambda + systemd service)
- **Automated Deregistration**: Prevents orphaned runners in GitHub organization using lifecycle hooks and Lambda functions
- **Unified Logging**: Centralized CloudWatch logging for complete runner lifecycle tracking
- **Network Security**: Runs in private subnets with NAT Gateway for outbound internet access
- **Encryption**: KMS encryption for secrets, CloudWatch logs, EFS storage, SNS topics, and Lambda functions
- **Performance Optimization**: EFS with tuned NFS parameters and Lambda layer for reduced cold start times
- **Cost Optimization**: EFS storage for shared runner workspace and dependency caching to reduce startup time

## Architecture

The solution deploys:
- **VPC with public/private subnets** across multiple Availability Zones
- **Auto Scaling Group** with EC2 instances running GitHub Actions runners
- **Auto Scaling Lifecycle Hooks** for graceful runner deregistration on instance termination
- **SNS Topic** for lifecycle event notifications with KMS encryption
- **Lambda function** for automated runner deregistration via GitHub API
- **Lambda Layer** with PyJWT and cryptography dependencies for optimized performance
- **Dead Letter Queue** for Lambda error handling and retry mechanisms
- **EFS file system** for shared runner workspace storage with optimized NFS parameters
- **CloudWatch log groups** for unified lifecycle logging with structured format
- **Secrets Manager** for secure GitHub App credentials storage
- **SSM Parameter Store** for runner configuration scripts and deregistration service
- **Systemd Service** for backup deregistration mechanism

## Prerequisites

Before deploying this infrastructure, please ensure the following prerequisites are met:

### AWS Setup
- An AWS account with appropriate permissions to create and manage the resources included in this repository
- An OpenID Connect identity provider created in AWS IAM with a trust relationship to this GitHub repository ([detailed setup guide](https://skundunotes.com/2023/02/28/securely-integrate-aws-credentials-with-github-actions-using-openid-connect/))
- The ARN of the IAM Role stored as a GitHub secret for use in the `terraform.yml` workflow and referred via `${{ secrets.IAM_ROLE }}`.

### GitHub Setup
- A GitHub organization where the self-hosted runners will be registered
- A GitHub App created in the organization with the following permissions:
  - Repository permissions: `Actions (Read)`, `Administration (Read)`, `Metadata (Read)`
  - Organization permissions: `Self-hosted runners (Write)`
- GitHub App credentials (App ID, Installation ID, and Private Key) stored in AWS Secrets Manager

### Infracost Integration (Optional)
- An `INFRACOST_API_KEY` stored as a GitHub Actions secret for cost estimation
- A GitHub Actions variable `INFRACOST_SCAN_TYPE` set to either `hcl_code` or `tf_plan` depending on the desired scan type

## Usage

This infrastructure is deployed automatically using the GitHub Actions workflow defined in `.github/workflows/terraform.yml`. The workflow provides complete CI/CD automation with security scanning, cost estimation, and infrastructure deployment.

### Automated Deployment Pipeline

The `terraform.yml` workflow includes the following automated stages:

#### 1. **Terraform Validation and Planning**
- **Terraform Format Check**: Ensures code follows canonical formatting
- **Terraform Validation**: Validates configuration syntax and logic
- **Terraform Plan**: Generates execution plan showing proposed changes
- **Plan Output**: Posts detailed plan as PR comment for review

#### 2. **Security and Cost Analysis**
- **Checkov Security Scan**: Identifies security misconfigurations and compliance issues
- **Infracost Analysis**: Provides cost estimates for infrastructure changes
- **Cost Comparison**: Shows cost diff between current and proposed infrastructure

#### 3. **Automated Deployment**
- **Trigger**: Automatically deploys on pushes to `main` branch
- **Authentication**: Uses OIDC for secure, temporary AWS credentials
- **Terraform Apply**: Provisions infrastructure with GitHub App credentials
- **State Management**: Maintains Terraform state in remote backend

### Configuration Steps

#### 1. Configure GitHub Secrets
Set up the following secrets in your GitHub repository:
- `IAM_ROLE`: ARN of the OIDC-assumable IAM role
- `THIS_GITHUB_APP_ID`: GitHub App ID for runner authentication
- `THIS_GITHUB_INSTALLATION_ID`: GitHub App Installation ID
- `THIS_GITHUB_PRIVATE_KEY`: GitHub App private key
- `INFRACOST_API_KEY`: API key for cost estimation (optional)

#### 2. Store GitHub App Credentials in AWS
Create a secret in AWS Secrets Manager with GitHub App credentials:
```json
{
  "app_id": "123456",
  "installation_id": "12345678",
  "private_key": "the-private-key"
}
```

### Deployment Process

#### Pull Request Workflow
1. **Create Feature Branch**: Make changes in a feature branch
2. **Open Pull Request**: Triggers validation, security scan, and cost analysis
3. **Review Automation**: 
   - Terraform plan posted as PR comment
   - Checkov findings displayed in PR
   - Infracost analysis shows cost impact
4. **Merge to Main**: Triggers automatic deployment

#### Production Deployment
1. **Automatic Trigger**: Merge to `main` branch starts deployment
2. **Secure Authentication**: OIDC provides temporary AWS credentials
3. **Infrastructure Provisioning**: Terraform applies changes to AWS
4. **Validation**: Deployment success confirmed through workflow logs

### Monitoring and Validation

#### Deployment Status
- **Workflow Badge**: Click the terraform-infra-provisioning badge above for real-time status
- **GitHub Actions Logs**: Detailed logs available in the Actions tab
- **Terraform State**: Remote state tracks all deployed resources

#### Runner Validation
- **GitHub Organization**: Verify runners appear in Actions settings
- **CloudWatch Logs**: Monitor registration process in `/{name}/lifecycle` log group
- **Auto Scaling Group**: Check EC2 instances are launching successfully
- **EFS Mount**: Verify shared workspace storage is accessible

## Configuration

### Key Variables
The infrastructure can be customized by modifying the default values in `variables.tf`:

- `region`: AWS region for deployment (default: "us-west-2")
- `name`: Prefix for all resource names (default: "github-self-hosted-runner")
- `github_organization`: GitHub organization name (must be updated)
- `runner_instance_type`: EC2 instance type for runners (default: "t3.medium")
- `runner_min_size`: Minimum number of runners (default: 1)
- `runner_max_size`: Maximum number of runners
- `runner_desired_capacity`: Desired number of runners

### Logging Structure
The solution provides unified logging with the following structure:
```
/{name}/lifecycle/
├── {instance-id}/registration
├── {instance-id}/execution
└── {instance-id}/deregistration
```

## Security Considerations

- All runners operate in private subnets with no direct internet access
- GitHub App authentication provides scoped, time-limited access tokens
- All secrets are encrypted using customer-managed KMS keys
- CloudWatch logs are encrypted at rest with KMS
- EFS file system uses encryption in transit and at rest
- SNS topics and Lambda functions encrypted with customer-managed KMS keys
- Lambda functions run in VPC with private subnets for enhanced security
- Dead Letter Queue encrypted for secure error message handling
- Security groups restrict network access to necessary ports only
- IAM roles follow least privilege principle with minimal required permissions

## Troubleshooting

### Common Issues
1. **Runner registration failures**: Check GitHub App permissions and credentials in Secrets Manager
2. **Instance launch failures**: Verify VPC configuration and security group rules
3. **Deregistration issues**: Check Lambda function logs in CloudWatch and dead letter queue messages
4. **Network connectivity**: Ensure NAT Gateway is properly configured for private subnet internet access
5. **Lambda deregistration failures**: Check Lambda function logs, VPC configuration, and GitHub API connectivity
6. **EFS mount issues**: Verify NFS security group rules and mount target availability in all AZs
7. **Lifecycle hook timeouts**: Check 5-minute timeout configuration and Lambda function performance metrics
8. **SNS delivery failures**: Verify SNS topic permissions and Lambda subscription configuration

### Monitoring
- CloudWatch logs provide detailed lifecycle tracking with structured format
- Auto Scaling Group metrics show scaling activities and lifecycle hook status
- Lambda function metrics indicate deregistration success rates and error patterns
- Dead Letter Queue metrics show failed Lambda executions requiring investigation
- EFS performance metrics monitor storage throughput and connection counts
- SNS topic metrics track message delivery and failure rates

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please ensure that:
- Code follows Terraform best practices
- All resources include appropriate tags
- Security considerations are addressed
- Documentation is updated for any new features

If you find any issues or have suggestions for improvement, please feel free to open an issue.

## License

This code is released under the Unlicense License. See [LICENSE](LICENSE) for details. 