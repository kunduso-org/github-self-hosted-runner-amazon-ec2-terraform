#!/bin/bash
set -e

# Setup logging
LOG_FILE="/var/log/github-runner-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "$(date): Starting GitHub runner setup"

# Setup CloudWatch logging immediately
echo "$(date): Setting up CloudWatch logging"
apt-get update -qq && apt-get install -y -qq awscli curl jq

# Get instance ID
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "$(date): Instance ID: $INSTANCE_ID"

# Function to send logs to CloudWatch
send_logs() {
  # Create log stream if it doesn't exist
  aws logs create-log-stream \
    --log-group-name "${log_group_name}" \
    --log-stream-name "$INSTANCE_ID-setup" \
    --region "${region}" || true
  
  # Get log content and timestamp
  local content=$(cat $LOG_FILE | sed 's/"/\\"/g')
  local timestamp=$(date +%s000)
  
  # Create JSON for log events
  echo "{\"logEvents\": [{\"timestamp\": $timestamp, \"message\": \"$content\"}]}" > /tmp/log-events.json
  
  # Send logs
  aws logs put-log-events \
    --log-group-name "${log_group_name}" \
    --log-stream-name "$INSTANCE_ID-setup" \
    --log-events file:///tmp/log-events.json \
    --region "${region}" || true
    
  echo "$(date): Logs sent to CloudWatch"
}

# Send logs every minute in background
(while true; do send_logs; sleep 60; done) &

# Update system
echo "$(date): Updating system packages"
apt-get update || { echo "$(date): ERROR - Failed to update packages"; exit 1; }
apt-get install -y python3-pip amazon-efs-utils nfs-common || { echo "$(date): ERROR - Failed to install packages"; exit 1; }
pip3 install PyJWT requests || { echo "$(date): ERROR - Failed to install Python packages"; exit 1; }
echo "$(date): System packages updated successfully"

# Install CloudWatch Logs agent
echo "$(date): Installing CloudWatch Logs agent"
curl -o /tmp/amazon-cloudwatch-agent.deb https://s3.amazonaws.com/amazoncloudwatch-agent/debian/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i /tmp/amazon-cloudwatch-agent.deb
rm /tmp/amazon-cloudwatch-agent.deb

# Configure CloudWatch Logs agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
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
          },
          {
            "file_path": "/home/runner/_diag/*.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}-diag",
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
mkdir -p /home/runner/_work || { echo "$(date): ERROR - Failed to create work directory"; exit 1; }
echo "${efs_dns_name}:/ /home/runner/_work nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0" >> /etc/fstab
mount /home/runner/_work || { echo "$(date): ERROR - Failed to mount EFS"; exit 1; }
echo "$(date): EFS mounted successfully"

# Install Docker
echo "$(date): Installing Docker"
curl -fsSL https://get.docker.com -o get-docker.sh || { echo "$(date): ERROR - Failed to download Docker install script"; exit 1; }
sh get-docker.sh || { echo "$(date): ERROR - Failed to install Docker"; exit 1; }
usermod -aG docker ubuntu || { echo "$(date): ERROR - Failed to add ubuntu to docker group"; exit 1; }
echo "$(date): Docker installed successfully"

# Create runner user
echo "$(date): Creating runner user"
useradd -m -s /bin/bash runner || { echo "$(date): ERROR - Failed to create runner user"; exit 1; }
usermod -aG docker runner || { echo "$(date): ERROR - Failed to add runner to docker group"; exit 1; }
echo "$(date): Runner user created successfully"

# Download GitHub Actions runner
echo "$(date): Downloading GitHub Actions runner"
cd /home/runner
curl -o actions-runner-linux-x64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz || { echo "$(date): ERROR - Failed to download GitHub runner"; exit 1; }
tar xzf actions-runner-linux-x64-2.321.0.tar.gz || { echo "$(date): ERROR - Failed to extract GitHub runner"; exit 1; }
chown -R runner:runner /home/runner || { echo "$(date): ERROR - Failed to change ownership"; exit 1; }
echo "$(date): GitHub Actions runner downloaded successfully"

# Get GitHub credentials from Secrets Manager
echo "$(date): Retrieving GitHub credentials from Secrets Manager"
SECRET=$(aws secretsmanager get-secret-value --secret-id "${secret_name}" --region "${region}" --query SecretString --output text) || { echo "$(date): ERROR - Failed to retrieve secret from Secrets Manager"; exit 1; }
APP_ID=$(echo $SECRET | jq -r '.app_id') || { echo "$(date): ERROR - Failed to parse app_id from secret"; exit 1; }
INSTALLATION_ID=$(echo $SECRET | jq -r '.installation_id') || { echo "$(date): ERROR - Failed to parse installation_id from secret"; exit 1; }
PRIVATE_KEY=$(echo $SECRET | jq -r '.private_key') || { echo "$(date): ERROR - Failed to parse private_key from secret"; exit 1; }

# For debugging (showing only non-sensitive data)
echo "$(date): App ID: $APP_ID"
echo "$(date): Installation ID: $INSTALLATION_ID"
echo "$(date): Organization: ${github_organization}"
echo "$(date): GitHub credentials retrieved successfully"

# Generate JWT token for GitHub App authentication
echo "$(date): Generating GitHub App JWT token"

# Export variables for Python to use
export APP_ID_VAR="$APP_ID"
export INSTALLATION_ID_VAR="$INSTALLATION_ID"
export PRIVATE_KEY_VAR="$PRIVATE_KEY"

python3 -c "
import jwt
import time
import json
import requests
import sys
import os

try:
    # Get variables from environment
    app_id = os.environ['APP_ID_VAR']
    installation_id = os.environ['INSTALLATION_ID_VAR']
    private_key = os.environ['PRIVATE_KEY_VAR']
    
    # Create JWT
    payload = {
        'iat': int(time.time()),
        'exp': int(time.time()) + 600,
        'iss': app_id
    }
    
    token = jwt.encode(payload, private_key, algorithm='RS256')
    
    # Get installation access token
    headers = {
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    print(f'Making request to: https://api.github.com/app/installations/{installation_id}/access_tokens', file=sys.stderr)
    response = requests.post(
        f'https://api.github.com/app/installations/{installation_id}/access_tokens',
        headers=headers
    )
    
    if response.status_code != 201:
        print(f'ERROR: Failed to get access token. Status: {response.status_code}, Response: {response.text}', file=sys.stderr)
        sys.exit(1)
    
    access_token = response.json()['token']
    print(access_token)
except Exception as e:
    print(f'ERROR: Exception in JWT generation: {str(e)}', file=sys.stderr)
    sys.exit(1)
" > /tmp/github_token || { echo "$(date): ERROR - Failed to generate JWT token"; exit 1; }

GITHUB_TOKEN=$(cat /tmp/github_token) || { echo "$(date): ERROR - Failed to read GitHub token"; exit 1; }
rm /tmp/github_token
echo "$(date): GitHub App JWT token generated successfully"

# Test connectivity to GitHub API
echo "$(date): Testing connectivity to GitHub API"
curl -s https://api.github.com/zen
echo "$(date): GitHub API connectivity test completed"

# Get registration token for organization
echo "$(date): Getting registration token for GitHub organization"
ORG_URL="https://github.com/${github_organization}"
echo "$(date): Organization URL: $ORG_URL"
echo "$(date): GitHub Token length: ${#GITHUB_TOKEN}"

# Debug API call
echo "$(date): Making API call for registration token"
CURL_RESPONSE=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/${github_organization}/actions/runners/registration-token")
echo "$(date): API response: $(echo $CURL_RESPONSE | jq -c .)"

REG_TOKEN=$(echo "$CURL_RESPONSE" | jq -r '.token')

if [ "$REG_TOKEN" = "null" ] || [ -z "$REG_TOKEN" ]; then
    echo "$(date): ERROR - Registration token is null or empty"
    echo "$(date): Full API response: $CURL_RESPONSE"
    send_logs
    exit 1
fi
echo "$(date): Registration token obtained successfully"

# Configure and start runner
echo "$(date): Configuring GitHub runner"
chown -R runner:runner /home/runner/_work || { echo "$(date): ERROR - Failed to set permissions on work directory"; exit 1; }
sudo -u runner ./config.sh --url "$ORG_URL" --token "$REG_TOKEN" --name "$INSTANCE_ID" --work /home/runner/_work --replace --unattended || { echo "$(date): ERROR - Failed to configure runner"; exit 1; }
echo "$(date): GitHub runner configured successfully"

echo "$(date): Starting GitHub runner"
sudo -u runner nohup ./run.sh > /var/log/github-runner.log 2>&1 &
echo "$(date): GitHub runner started in background"

# Install runner as service
echo "$(date): Installing runner as service"
./svc.sh install runner || { echo "$(date): ERROR - Failed to install runner service"; exit 1; }
./svc.sh start || { echo "$(date): ERROR - Failed to start runner service"; exit 1; }
echo "$(date): Runner service installed and started successfully"

# Final log send
send_logs

echo "$(date): GitHub runner setup completed successfully"