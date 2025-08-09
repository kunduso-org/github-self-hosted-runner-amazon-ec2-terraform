#!/bin/bash
# GitHub Runner Deregistration Script
# Runs during system shutdown to clean up runner from GitHub

set -e

DEREGISTRATION_LOG_FILE="/var/log/github-runner-deregistration.log"
exec > >(tee -a $DEREGISTRATION_LOG_FILE)
exec 2>&1

echo "$(date): Starting GitHub runner deregistration"

# Get instance ID
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
if [ -n "$TOKEN" ]; then
    INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
else
    INSTANCE_ID="unknown"
fi

echo "$(date): Instance ID: $INSTANCE_ID"

# Change to runner directory
cd /home/runner || {
    echo "$(date): ERROR - Runner directory not found"
    exit 1
}

# Get GitHub credentials from Secrets Manager
echo "$(date): Retrieving GitHub credentials"
SECRET=$(aws secretsmanager get-secret-value --secret-id "${secret_name}" --region "${region}" --query SecretString --output text 2>/dev/null || echo "")

if [ -z "$SECRET" ]; then
    echo "$(date): ERROR - Failed to retrieve GitHub credentials"
    exit 1
fi

APP_ID=$(echo $SECRET | jq -r '.app_id' 2>/dev/null || echo "")
INSTALLATION_ID=$(echo $SECRET | jq -r '.installation_id' 2>/dev/null || echo "")
PRIVATE_KEY=$(echo $SECRET | jq -r '.private_key' 2>/dev/null || echo "")

if [ -z "$APP_ID" ] || [ -z "$INSTALLATION_ID" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "$(date): ERROR - Invalid GitHub credentials"
    exit 1
fi

# Generate JWT token
echo "$(date): Generating GitHub App JWT token"
python3 -c "
import jwt
import time
import requests
import sys

try:
    private_key = '''$PRIVATE_KEY'''.replace('\\\\n', '\n')
    
    payload = {
        'iat': int(time.time()),
        'exp': int(time.time()) + 600,
        'iss': '$APP_ID'
    }
    
    token = jwt.encode(payload, private_key, algorithm='RS256')
    
    headers = {
        'Authorization': 'Bearer ' + str(token),
        'Accept': 'application/vnd.github.v3+json'
    }
    
    response = requests.post(
        'https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens',
        headers=headers,
        timeout=30
    )
    
    if response.status_code == 201:
        print(response.json()['token'])
    else:
        sys.exit(1)
        
except Exception as e:
    sys.exit(1)
" > /tmp/github_token.txt 2>/dev/null

if [ $? -ne 0 ] || [ ! -s /tmp/github_token.txt ]; then
    echo "$(date): ERROR - Failed to generate GitHub token"
    exit 1
fi

GITHUB_TOKEN=$(cat /tmp/github_token.txt)
rm -f /tmp/github_token.txt

echo "$(date): GitHub token generated successfully"

# Get removal token
echo "$(date): Getting removal token"
REMOVAL_RESPONSE=$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/orgs/${github_organization}/actions/runners/remove-token" 2>/dev/null || echo "")

REMOVAL_TOKEN=$(echo "$REMOVAL_RESPONSE" | jq -r '.token' 2>/dev/null || echo "")

if [ -z "$REMOVAL_TOKEN" ] || [ "$REMOVAL_TOKEN" = "null" ]; then
    echo "$(date): ERROR - Failed to get removal token"
    exit 1
fi

echo "$(date): Removal token obtained"

# Remove runner
echo "$(date): Removing runner from GitHub"
if sudo -u runner ./config.sh remove --token "$REMOVAL_TOKEN" --unattended 2>&1; then
    echo "$(date): Runner successfully deregistered from GitHub"
else
    echo "$(date): WARNING - Runner deregistration may have failed"
fi

echo "$(date): GitHub runner deregistration completed"