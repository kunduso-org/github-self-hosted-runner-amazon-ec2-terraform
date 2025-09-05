#!/bin/bash
set -e

# Setup logging
REGISTRATION_LOG_FILE="/var/log/github-runner-registration.log"
exec > >(tee -a $REGISTRATION_LOG_FILE)
exec 2>&1

echo "$(date): Starting GitHub runner setup"

# Network connectivity validation
echo "$(date): Validating network connectivity..."
retry_count=0
max_retries=12  # 2 minutes total

until curl -s --connect-timeout 5 https://aws.amazon.com > /dev/null; do
    retry_count=$((retry_count + 1))
    if [ $retry_count -ge $max_retries ]; then
        echo "$(date): ERROR - Network connectivity failed after $max_retries attempts"
        exit 1
    fi
    echo "$(date): Network not ready, waiting... (attempt $retry_count/$max_retries)"
    sleep 10
done

echo "$(date): Network connectivity confirmed"

# Test critical AWS services
echo "$(date): Testing AWS services connectivity..."
aws_services=(
    "https://s3.${region}.amazonaws.com"
    "https://secretsmanager.${region}.amazonaws.com"
    "https://logs.${region}.amazonaws.com"
)

for service in "$${aws_services[@]}"; do
    echo "$(date): Testing connectivity to $service..."
    if ! curl -s --connect-timeout 10 "$service" > /dev/null; then
        echo "$(date): WARNING - Cannot reach $service"
    else
        echo "$(date): Successfully connected to $service"
    fi
done

echo "$(date): AWS services connectivity test completed"

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
            "file_path": "/var/log/github-runner-registration.log",
            "log_group_name": "${lifecycle_log_group_name}",
            "log_stream_name": "{instance_id}/registration",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/github-runner-deregistration.log",
            "log_group_name": "${lifecycle_log_group_name}",
            "log_stream_name": "{instance_id}/deregistration",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/github-runner.log",
            "log_group_name": "${lifecycle_log_group_name}",
            "log_stream_name": "{instance_id}/execution",
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

# Install Terraform
echo "$(date): Installing Terraform"
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt update && apt install -y terraform
echo "$(date): Terraform installed successfully"

# Create runner user
echo "$(date): Creating runner user"
useradd -m -s /bin/bash runner
usermod -aG docker runner
# Fix EFS mount ownership
chown -R runner:runner /home/runner/_work
echo "$(date): Runner user created successfully and EFS ownership fixed"

# Download GitHub Actions runner
echo "$(date): Downloading GitHub Actions runner"
cd /home/runner
curl -o actions-runner-linux-x64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
tar xzf actions-runner-linux-x64-2.321.0.tar.gz
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

print('DEBUG: Starting JWT script', file=sys.stderr)

try:
    print('DEBUG: Reading environment variables', file=sys.stderr)
    app_id = os.environ['APP_ID']
    installation_id = os.environ['INSTALLATION_ID']
    private_key = os.environ['PRIVATE_KEY']
    
    # Convert escaped newlines to actual newlines
    private_key = private_key.replace('\\n', '\n')
    
    print('DEBUG: App ID: ' + app_id, file=sys.stderr)
    print('DEBUG: Installation ID: ' + installation_id, file=sys.stderr)
    print('DEBUG: Private key length: ' + str(len(private_key)), file=sys.stderr)
    
    print('DEBUG: Creating JWT payload', file=sys.stderr)
    payload = {
        'iat': int(time.time()),
        'exp': int(time.time()) + 600,
        'iss': app_id
    }
    
    print('DEBUG: Encoding JWT token', file=sys.stderr)
    token = jwt.encode(payload, private_key, algorithm='RS256')
    print('DEBUG: JWT token created successfully', file=sys.stderr)
    
    print('DEBUG: Preparing API request headers', file=sys.stderr)
    headers = {
        'Authorization': 'Bearer ' + str(token),
        'Accept': 'application/vnd.github.v3+json'
    }
    
    api_url = 'https://api.github.com/app/installations/' + installation_id + '/access_tokens'
    print('DEBUG: Making request to: ' + api_url, file=sys.stderr)
    
    response = requests.post(api_url, headers=headers, timeout=30)
    
    print('DEBUG: API response status: ' + str(response.status_code), file=sys.stderr)
    
    if response.status_code != 201:
        print('ERROR: Failed to get access token. Status: ' + str(response.status_code))
        print('Response body: ' + response.text)
        sys.exit(1)
    
    print('DEBUG: Parsing response JSON', file=sys.stderr)
    access_token = response.json()['token']
    print('DEBUG: Access token obtained successfully', file=sys.stderr)
    print(access_token)
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
EOFPYTHON

# Pass variables to Python script via environment
export APP_ID="$APP_ID"
export INSTALLATION_ID="$INSTALLATION_ID"
export PRIVATE_KEY="$PRIVATE_KEY"

echo "$(date): Executing JWT generation script..."

# Run JWT script with timeout
if ! timeout 60 python3 /tmp/jwt_script.py > /tmp/jwt_output.txt 2> /tmp/jwt_error.txt; then
    JWT_EXIT_CODE=$?
    echo "$(date): ERROR - JWT generation failed or timed out with exit code $JWT_EXIT_CODE"
    echo "$(date): Check CloudWatch logs for detailed error information"
    rm -f /tmp/jwt_script.py /tmp/jwt_output.txt /tmp/jwt_error.txt
    exit 1
fi

GITHUB_TOKEN=$(cat /tmp/jwt_output.txt)
rm -f /tmp/jwt_script.py /tmp/jwt_output.txt /tmp/jwt_error.txt

if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "null" ]; then
    echo "$(date): ERROR - JWT token is empty or null"
    exit 1
fi

echo "$(date): GitHub App JWT token generated successfully"

# Get registration token for organization
echo "$(date): Getting registration token for GitHub organization"
ORG_URL="https://github.com/${github_organization}"
echo "$(date): Organization URL: $ORG_URL"

echo "$(date): Making API request to GitHub..."
API_RESPONSE=$(curl -s -w "HTTP_CODE:%%{http_code}" -X POST -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/${github_organization}/actions/runners/registration-token")
HTTP_CODE=$(echo "$API_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
API_BODY=$(echo "$API_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')

echo "$(date): GitHub API response code: $HTTP_CODE"

if [ "$HTTP_CODE" != "201" ]; then
    echo "$(date): ERROR - GitHub API request failed with HTTP code $HTTP_CODE"
    echo "$(date): Check GitHub App permissions and installation"
    exit 1
fi

REG_TOKEN=$(echo "$API_BODY" | jq -r '.token')

if [ "$REG_TOKEN" = "null" ] || [ -z "$REG_TOKEN" ]; then
    echo "$(date): ERROR - Registration token is null or empty"
    echo "$(date): GitHub API returned invalid response"
    exit 1
fi
echo "$(date): Registration token obtained successfully"

# Configure and start runner
echo "$(date): Configuring GitHub runner"
echo "$(date): Running config.sh with parameters:"
echo "$(date): URL: $ORG_URL"
echo "$(date): Name: $INSTANCE_ID"
echo "$(date): Labels: ${region}"

if ! sudo -u runner ./config.sh --url "$ORG_URL" --token "$REG_TOKEN" --name "$INSTANCE_ID" --work /home/runner/_work --labels "${region}" --replace --unattended 2>&1; then
    echo "$(date): ERROR - Runner configuration failed"
    exit 1
fi
echo "$(date): GitHub runner configured successfully"

echo "$(date): Starting GitHub runner"
sudo -u runner nohup ./run.sh > /var/log/github-runner.log 2>&1 &
echo "$(date): GitHub runner started in background"

# Install runner as service
echo "$(date): Installing runner as service"
if ! ./svc.sh install runner 2>&1; then
    echo "$(date): ERROR - Failed to install runner service"
    exit 1
fi

if ! ./svc.sh start 2>&1; then
    echo "$(date): ERROR - Failed to start runner service"
    exit 1
fi
echo "$(date): Runner service installed and started successfully"
echo "$(date): GitHub runner setup completed successfully"