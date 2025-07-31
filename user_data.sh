#!/bin/bash
set -e

# Setup logging
LOG_FILE="/var/log/github-runner-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "$(date): Starting GitHub runner setup"

# Get instance ID for runner naming using IMDSv2
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)

# Update system
echo "$(date): Updating system packages"
apt-get update
apt-get install -y curl jq awscli python3-pip git binutils nfs-common
pip3 install PyJWT requests
echo "$(date): System packages updated successfully"

# Install NFS client for EFS mounting
echo "$(date): Installing NFS client"
apt-get -y install nfs-common
echo "$(date): NFS client installed successfully"

# Setup CloudWatch logging
echo "$(date): Setting up CloudWatch logging"

# Install CloudWatch Logs agent
curl -o /tmp/amazon-cloudwatch-agent.deb https://s3.amazonaws.com/amazoncloudwatch-agent/debian/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i /tmp/amazon-cloudwatch-agent.deb
rm /tmp/amazon-cloudwatch-agent.deb

# Configure CloudWatch Logs agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/github-runner-setup.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}-setup",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/github-runner.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}-runner",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
echo "$(date): CloudWatch Logs agent configured and started"

# Setup EFS mount
echo "$(date): Setting up EFS mount"
mkdir -p /home/runner/_work
echo "${efs_dns_name}:/ /home/runner/_work nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0" >> /etc/fstab
mount /home/runner/_work
echo "$(date): EFS mounted successfully"

# Install Docker
echo "$(date): Installing Docker"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu
echo "$(date): Docker installed successfully"

# Create runner user
echo "$(date): Creating runner user"
useradd -m -s /bin/bash runner
usermod -aG docker runner
echo "$(date): Runner user created successfully"

# Download GitHub Actions runner
echo "$(date): Downloading GitHub Actions runner"
cd /home/runner
curl -o actions-runner-linux-x64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
tar xzf actions-runner-linux-x64-2.321.0.tar.gz
chown -R runner:runner /home/runner
echo "$(date): GitHub Actions runner downloaded successfully"

# Get GitHub credentials from Secrets Manager
echo "$(date): Retrieving GitHub credentials from Secrets Manager"
SECRET=$(aws secretsmanager get-secret-value --secret-id "${secret_name}" --region "${region}" --query SecretString --output text)
APP_ID=$(echo $SECRET | jq -r '.app_id')
INSTALLATION_ID=$(echo $SECRET | jq -r '.installation_id')
PRIVATE_KEY=$(echo $SECRET | jq -r '.private_key')

# For debugging (showing only non-sensitive data)
echo "$(date): App ID: $APP_ID"
echo "$(date): Installation ID: $INSTALLATION_ID"
echo "$(date): Organization: ${github_organization}"
echo "$(date): GitHub credentials retrieved successfully"

# Generate JWT token for GitHub App authentication
echo "$(date): Generating GitHub App JWT token"

# Create Python script for JWT generation
cat > /tmp/jwt_script.py <<EOFPYTHON
import jwt
import time
import json
import requests
import sys
import os

try:
    app_id = os.environ['APP_ID']
    installation_id = os.environ['INSTALLATION_ID']
    private_key = os.environ['PRIVATE_KEY']
    
    payload = {
        'iat': int(time.time()),
        'exp': int(time.time()) + 600,
        'iss': app_id
    }
    
    token = jwt.encode(payload, private_key, algorithm='RS256')
    
    headers = {
        'Authorization': 'Bearer ' + str(token),
        'Accept': 'application/vnd.github.v3+json'
    }
    
    response = requests.post(
        'https://api.github.com/app/installations/' + installation_id + '/access_tokens',
        headers=headers
    )
    
    if response.status_code != 201:
        print('ERROR: Failed to get access token. Status: ' + str(response.status_code))
        sys.exit(1)
    
    access_token = response.json()['token']
    print(access_token)
except Exception as e:
    print('ERROR: ' + str(e))
    sys.exit(1)
EOFPYTHON

# Pass variables to Python script via environment
export APP_ID="$APP_ID"
export INSTALLATION_ID="$INSTALLATION_ID"
export PRIVATE_KEY="$PRIVATE_KEY"

GITHUB_TOKEN=$(python3 /tmp/jwt_script.py)
rm /tmp/jwt_script.py
echo "$(date): GitHub App JWT token generated successfully"

# Get registration token for organization
echo "$(date): Getting registration token for GitHub organization"
ORG_URL="https://github.com/${github_organization}"
echo "$(date): Organization URL: $ORG_URL"

# Get registration token
echo "$(date): Getting registration token for GitHub organization"
ORG_URL="https://github.com/${github_organization}"
REG_TOKEN=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/${github_organization}/actions/runners/registration-token" | jq -r '.token')

if [ "$REG_TOKEN" = "null" ] || [ -z "$REG_TOKEN" ]; then
    echo "$(date): ERROR - Registration token is null or empty"
    exit 1
fi
echo "$(date): Registration token obtained successfully"

# Configure and start runner
echo "$(date): Configuring GitHub runner"
chown -R runner:runner /home/runner/_work
sudo -u runner ./config.sh --url "$ORG_URL" --token "$REG_TOKEN" --name "$INSTANCE_ID" --work /home/runner/_work --labels "${region}" --replace --unattended
echo "$(date): GitHub runner configured successfully"

echo "$(date): Starting GitHub runner"
sudo -u runner nohup ./run.sh > /var/log/github-runner.log 2>&1 &
echo "$(date): GitHub runner started in background"

# Install runner as service
echo "$(date): Installing runner as service"
./svc.sh install runner
./svc.sh start
echo "$(date): Runner service installed and started successfully"

echo "$(date): GitHub runner setup completed successfully"