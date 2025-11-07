"""
Utility functions for AWS Batch jobs.
"""

import os
import json
import logging
import sys
from typing import Any, Optional
import boto3
from botocore.exceptions import ClientError


def setup_logging(level: str = None) -> logging.Logger:
    """
    Set up structured logging for the application.
    
    Args:
        level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        
    Returns:
        Configured logger instance
    """
    if level is None:
        level = os.getenv('LOG_LEVEL', 'INFO').upper()
    
    # Configure logging format
    logging.basicConfig(
        level=getattr(logging, level),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        stream=sys.stdout
    )
    
    logger = logging.getLogger('batch-job')
    logger.setLevel(getattr(logging, level))
    
    return logger


def get_secret(secret_name: str, region: str = None) -> dict:
    """
    Retrieve a secret from AWS Secrets Manager.
    
    Args:
        secret_name: Name of the secret
        region: AWS region (defaults to AWS_REGION env var)
        
    Returns:
        Secret value as dictionary
        
    Raises:
        ClientError: If secret cannot be retrieved
    """
    if region is None:
        region = os.getenv('AWS_REGION', 'us-east-1')
    
    client = boto3.client('secretsmanager', region_name=region)
    
    try:
        response = client.get_secret_value(SecretId=secret_name)
        
        if 'SecretString' in response:
            return json.loads(response['SecretString'])
        else:
            # Binary secret
            return response['SecretBinary']
            
    except ClientError as e:
        logging.error(f"Error retrieving secret {secret_name}: {e}")
        raise


def get_parameter(parameter_name: str, region: str = None, with_decryption: bool = True) -> str:
    """
    Retrieve a parameter from AWS Systems Manager Parameter Store.
    
    Args:
        parameter_name: Name of the parameter
        region: AWS region (defaults to AWS_REGION env var)
        with_decryption: Decrypt secure string parameters
        
    Returns:
        Parameter value
        
    Raises:
        ClientError: If parameter cannot be retrieved
    """
    if region is None:
        region = os.getenv('AWS_REGION', 'us-east-1')
    
    client = boto3.client('ssm', region_name=region)
    
    try:
        response = client.get_parameter(
            Name=parameter_name,
            WithDecryption=with_decryption
        )
        return response['Parameter']['Value']
        
    except ClientError as e:
        logging.error(f"Error retrieving parameter {parameter_name}: {e}")
        raise


def put_metric(metric_name: str, value: float, unit: str = 'Count',
               namespace: str = 'CustomBatch', dimensions: dict = None,
               region: str = None):
    """
    Publish a custom metric to CloudWatch.
    
    Args:
        metric_name: Name of the metric
        value: Metric value
        unit: Metric unit (Count, Seconds, Bytes, etc.)
        namespace: CloudWatch namespace
        dimensions: Dictionary of dimension name/value pairs
        region: AWS region (defaults to AWS_REGION env var)
    """
    if region is None:
        region = os.getenv('AWS_REGION', 'us-east-1')
    
    client = boto3.client('cloudwatch', region_name=region)
    
    metric_data = {
        'MetricName': metric_name,
        'Value': value,
        'Unit': unit
    }
    
    if dimensions:
        metric_data['Dimensions'] = [
            {'Name': k, 'Value': v} for k, v in dimensions.items()
        ]
    
    try:
        client.put_metric_data(
            Namespace=namespace,
            MetricData=[metric_data]
        )
        logging.debug(f"Published metric {metric_name}={value} to {namespace}")
        
    except ClientError as e:
        logging.warning(f"Error publishing metric {metric_name}: {e}")


def download_from_s3(s3_path: str, local_path: str = None, region: str = None) -> Optional[bytes]:
    """
    Download a file from S3.
    
    Args:
        s3_path: S3 path in format s3://bucket/key
        local_path: Local file path to save to (optional)
        region: AWS region (defaults to AWS_REGION env var)
        
    Returns:
        File contents as bytes if local_path is None, otherwise None
        
    Raises:
        ValueError: If S3 path format is invalid
        ClientError: If download fails
    """
    if not s3_path.startswith('s3://'):
        raise ValueError(f"Invalid S3 path: {s3_path}")
    
    # Parse S3 path
    parts = s3_path[5:].split('/', 1)
    if len(parts) != 2:
        raise ValueError(f"Invalid S3 path format: {s3_path}")
    
    bucket, key = parts
    
    if region is None:
        region = os.getenv('AWS_REGION', 'us-east-1')
    
    client = boto3.client('s3', region_name=region)
    
    try:
        if local_path:
            # Download to file
            client.download_file(bucket, key, local_path)
            logging.info(f"Downloaded {s3_path} to {local_path}")
            return None
        else:
            # Download to memory
            response = client.get_object(Bucket=bucket, Key=key)
            data = response['Body'].read()
            logging.info(f"Downloaded {s3_path} ({len(data)} bytes)")
            return data
            
    except ClientError as e:
        logging.error(f"Error downloading from {s3_path}: {e}")
        raise


def upload_to_s3(s3_path: str, data: Any, region: str = None, content_type: str = None):
    """
    Upload data to S3.
    
    Args:
        s3_path: S3 path in format s3://bucket/key
        data: Data to upload (bytes, string, or file path)
        region: AWS region (defaults to AWS_REGION env var)
        content_type: Content type for the object
        
    Raises:
        ValueError: If S3 path format is invalid
        ClientError: If upload fails
    """
    if not s3_path.startswith('s3://'):
        raise ValueError(f"Invalid S3 path: {s3_path}")
    
    # Parse S3 path
    parts = s3_path[5:].split('/', 1)
    if len(parts) != 2:
        raise ValueError(f"Invalid S3 path format: {s3_path}")
    
    bucket, key = parts
    
    if region is None:
        region = os.getenv('AWS_REGION', 'us-east-1')
    
    client = boto3.client('s3', region_name=region)
    
    try:
        extra_args = {}
        if content_type:
            extra_args['ContentType'] = content_type
        
        if isinstance(data, str) and os.path.isfile(data):
            # Upload from file
            client.upload_file(data, bucket, key, ExtraArgs=extra_args or None)
            logging.info(f"Uploaded {data} to {s3_path}")
        else:
            # Upload from memory
            if isinstance(data, str):
                data = data.encode('utf-8')
            client.put_object(Bucket=bucket, Key=key, Body=data, **extra_args)
            logging.info(f"Uploaded {len(data)} bytes to {s3_path}")
            
    except ClientError as e:
        logging.error(f"Error uploading to {s3_path}: {e}")
        raise


def parse_s3_path(s3_path: str) -> tuple:
    """
    Parse an S3 path into bucket and key.
    
    Args:
        s3_path: S3 path in format s3://bucket/key
        
    Returns:
        Tuple of (bucket, key)
        
    Raises:
        ValueError: If S3 path format is invalid
    """
    if not s3_path.startswith('s3://'):
        raise ValueError(f"Invalid S3 path: {s3_path}")
    
    parts = s3_path[5:].split('/', 1)
    if len(parts) != 2:
        raise ValueError(f"Invalid S3 path format: {s3_path}")
    
    return parts[0], parts[1]

