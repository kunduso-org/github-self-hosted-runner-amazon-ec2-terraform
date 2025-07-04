#!/bin/bash
set -e

# Update system
apt-get update
apt-get install -y curl jq awscli

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Create runner user
useradd -m -s /bin/bash runner
usermod -aG docker runner

# Download GitHub Actions runner
cd /home/runner
curl -o actions-runner-linux-x64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
tar xzf actions-runner-linux-x64-2.321.0.tar.gz
chown -R runner:runner /home/runner

# Get GitHub credentials from Secrets Manager
SECRET=$(aws secretsmanager get-secret-value --secret-id "${secret_name}" --region "${region}" --query SecretString --output text)
APP_ID=$(echo $SECRET | jq -r '.app_id')
INSTALLATION_ID=$(echo $SECRET | jq -r '.installation_id')
PRIVATE_KEY=$(echo $SECRET | jq -r '.private_key')

# Generate JWT token for GitHub App authentication
python3 -c "
import jwt
import time
import json
import requests

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

access_token = response.json()['token']
print(access_token)
" > /tmp/github_token

GITHUB_TOKEN=$(cat /tmp/github_token)
rm /tmp/github_token

# Get registration token for user account (all repositories)
ACCOUNT_URL="https://github.com/${github_username}"
REG_TOKEN=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/users/${github_username}/actions/runners/registration-token" | jq -r '.token')

# Configure and start runner
sudo -u runner ./config.sh --url "$ACCOUNT_URL" --token "$REG_TOKEN" --name "$(hostname)" --work _work --replace --unattended
sudo -u runner nohup ./run.sh &

# Install runner as service
./svc.sh install runner
./svc.sh start