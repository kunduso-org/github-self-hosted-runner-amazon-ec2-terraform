import json
import boto3
import jwt
import time
import requests
import os
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def log_deregistration_event(instance_id, status, message):
    """Log deregistration event to CloudWatch Logs."""
    try:
        logs_client = boto3.client('logs', region_name=os.environ['REGION'])
        log_group = os.environ['LIFECYCLE_LOG_GROUP']
        log_stream = f"{instance_id}/deregistration"
        
        # Create log stream if it doesn't exist
        try:
            logs_client.create_log_stream(
                logGroupName=log_group,
                logStreamName=log_stream
            )
        except logs_client.exceptions.ResourceAlreadyExistsException:
            pass
        except Exception as e:
            logger.error(f"Failed to create log stream: {e}")
            return
        
        # Get sequence token for existing stream
        try:
            response = logs_client.describe_log_streams(
                logGroupName=log_group,
                logStreamNamePrefix=log_stream
            )
            sequence_token = None
            if response['logStreams']:
                sequence_token = response['logStreams'][0].get('uploadSequenceToken')
        except Exception as e:
            logger.error(f"Failed to get sequence token: {e}")
            sequence_token = None
        
        # Put log event
        timestamp = int(time.time() * 1000)
        log_message = f"{datetime.utcnow().isoformat()}Z: [LIFECYCLE_HOOK] [{status}] {message}"
        
        put_events_params = {
            'logGroupName': log_group,
            'logStreamName': log_stream,
            'logEvents': [
                {
                    'timestamp': timestamp,
                    'message': log_message
                }
            ]
        }
        
        if sequence_token:
            put_events_params['sequenceToken'] = sequence_token
            
        logs_client.put_log_events(**put_events_params)
        
    except Exception as e:
        logger.error(f"Failed to log deregistration event: {e}")

def handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Parse SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        
        # Extract instance details
        instance_id = sns_message['EC2InstanceId']
        lifecycle_hook_name = sns_message['LifecycleHookName']
        auto_scaling_group_name = sns_message['AutoScalingGroupName']
        lifecycle_action_token = sns_message['LifecycleActionToken']
        
        logger.info(f"Processing termination for instance: {instance_id}")
        log_deregistration_event(instance_id, "STARTED", f"Lifecycle hook triggered for instance {instance_id}")
        
        # Get GitHub credentials
        secret_name = os.environ['SECRET_NAME']
        region = os.environ['REGION']
        github_organization = os.environ['GITHUB_ORGANIZATION']
        
        secrets_client = boto3.client('secretsmanager', region_name=region)
        secret_response = secrets_client.get_secret_value(SecretId=secret_name)
        secret_data = json.loads(secret_response['SecretString'])
        
        app_id = secret_data['app_id']
        installation_id = secret_data['installation_id']
        private_key = secret_data['private_key']
        
        # Generate JWT token
        payload = {
            'iat': int(time.time()),
            'exp': int(time.time()) + 600,
            'iss': app_id
        }
        
        token = jwt.encode(payload, private_key, algorithm='RS256')
        
        # Get GitHub access token
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.github.v3+json'
        }
        
        response = requests.post(
            f'https://api.github.com/app/installations/{installation_id}/access_tokens',
            headers=headers,
            timeout=30
        )
        
        if response.status_code != 201:
            logger.error(f"Failed to get GitHub access token: {response.status_code}")
            raise Exception("GitHub authentication failed")
        
        github_token = response.json()['token']
        
        # Get removal token
        headers = {
            'Authorization': f'token {github_token}',
            'Accept': 'application/vnd.github.v3+json'
        }
        
        response = requests.post(
            f'https://api.github.com/orgs/{github_organization}/actions/runners/remove-token',
            headers=headers,
            timeout=30
        )
        
        if response.status_code != 201:
            logger.error(f"Failed to get removal token: {response.status_code}")
            raise Exception("Failed to get removal token")
        
        removal_token = response.json()['token']
        
        # Find and remove runner by instance ID
        response = requests.get(
            f'https://api.github.com/orgs/{github_organization}/actions/runners',
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            runners = response.json()['runners']
            runner_to_remove = None
            
            for runner in runners:
                if runner['name'] == instance_id:
                    runner_to_remove = runner
                    break
            
            if runner_to_remove:
                runner_id = runner_to_remove['id']
                
                # Remove the runner
                response = requests.delete(
                    f'https://api.github.com/orgs/{github_organization}/actions/runners/{runner_id}',
                    headers=headers,
                    timeout=30
                )
                
                if response.status_code == 204:
                    logger.info(f"Successfully deregistered runner {instance_id}")
                    
                    # Log to CloudWatch for lifecycle tracking
                    log_deregistration_event(instance_id, "SUCCESS", f"Runner {instance_id} successfully deregistered")
                else:
                    logger.error(f"Failed to deregister runner: {response.status_code}")
                    log_deregistration_event(instance_id, "FAILED", f"Failed to deregister runner: {response.status_code}")
            else:
                logger.info(f"Runner {instance_id} not found in GitHub")
                log_deregistration_event(instance_id, "NOT_FOUND", f"Runner {instance_id} not found in GitHub")
        
        # Complete lifecycle action
        autoscaling_client = boto3.client('autoscaling', region_name=region)
        autoscaling_client.complete_lifecycle_action(
            LifecycleHookName=lifecycle_hook_name,
            AutoScalingGroupName=auto_scaling_group_name,
            InstanceId=instance_id,
            LifecycleActionToken=lifecycle_action_token,
            LifecycleActionResult='CONTINUE'
        )
        
        logger.info(f"Completed lifecycle action for instance {instance_id}")
        log_deregistration_event(instance_id, "COMPLETED", f"Lifecycle hook processing completed for instance {instance_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully processed termination for {instance_id}')
        }
        
    except Exception as e:
        logger.error(f"Error processing termination: {str(e)}")
        
        # Complete lifecycle action even on error to avoid hanging
        try:
            autoscaling_client = boto3.client('autoscaling', region_name=region)
            autoscaling_client.complete_lifecycle_action(
                LifecycleHookName=lifecycle_hook_name,
                AutoScalingGroupName=auto_scaling_group_name,
                InstanceId=instance_id,
                LifecycleActionToken=lifecycle_action_token,
                LifecycleActionResult='ABANDON'
            )
        except:
            pass
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing termination: {str(e)}')
        }