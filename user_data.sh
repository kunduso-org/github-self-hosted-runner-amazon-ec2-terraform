#!/bin/bash
set -e

# Setup logging
LOG_FILE="/var/log/github-runner-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "$(date): Starting GitHub runner setup"

# Update system
echo "$(date): Updating system packages"
apt-get update || { echo "$(date): ERROR - Failed to update packages"; exit 1; }
apt-get install -y curl jq awscli python3-pip || { echo "$(date): ERROR - Failed to install packages"; exit 1; }
pip3 install PyJWT requests || { echo "$(date): ERROR - Failed to install Python packages"; exit 1; }
echo "$(date): System packages updated successfully"

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
echo "$(date): GitHub credentials retrieved successfully"

# Generate JWT token for GitHub App authentication
echo "$(date): Generating GitHub App JWT token"
python3 -c "
import jwt
import time
import json
import requests
import sys

try:
    # Create JWT
    payload = {
        'iat': int(time.time()),
        'exp': int(time.time()) + 600,
        'iss': '$APP_ID'
    }
    
    private_key = '''$PRIVATE_KEY'''
    token = jwt.encode(payload, private_key, algorithm='RS256')
    
    # Get installation access token
    headers = {
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    response = requests.post(
        f'https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens',
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

# Get registration token for specific repository
echo "$(date): Getting registration token for GitHub repository"
REPO_URL="https://github.com/${github_repository}"
REG_TOKEN=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/${github_repository}/actions/runners/registration-token" | jq -r '.token') || { echo "$(date): ERROR - Failed to get registration token"; exit 1; }

if [ "$REG_TOKEN" = "null" ] || [ -z "$REG_TOKEN" ]; then
    echo "$(date): ERROR - Registration token is null or empty"
    exit 1
fi
echo "$(date): Registration token obtained successfully"

# Configure and start runner
echo "$(date): Configuring GitHub runner"
sudo -u runner ./config.sh --url "$REPO_URL" --token "$REG_TOKEN" --name "$(hostname)" --work _work --replace --unattended || { echo "$(date): ERROR - Failed to configure runner"; exit 1; }
echo "$(date): GitHub runner configured successfully"

echo "$(date): Starting GitHub runner"
sudo -u runner nohup ./run.sh > /var/log/github-runner.log 2>&1 &
echo "$(date): GitHub runner started in background"

# Install runner as service
echo "$(date): Installing runner as service"
./svc.sh install runner || { echo "$(date): ERROR - Failed to install runner service"; exit 1; }
./svc.sh start || { echo "$(date): ERROR - Failed to start runner service"; exit 1; }
echo "$(date): Runner service installed and started successfully"

echo "$(date): GitHub runner setup completed successfully"