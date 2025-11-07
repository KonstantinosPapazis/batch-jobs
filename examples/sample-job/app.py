#!/usr/bin/env python3
"""
Sample AWS Batch Job Application

This is an example batch job that demonstrates:
- Environment variable configuration
- AWS service integration (S3, Secrets Manager)
- Structured logging
- Error handling
- CloudWatch metrics
"""

import os
import sys
import json
import logging
from datetime import datetime
from typing import Dict, Any
import boto3
from botocore.exceptions import ClientError

# Import utility functions
from utils import (
    setup_logging,
    get_secret,
    get_parameter,
    put_metric,
    download_from_s3,
    upload_to_s3
)


# Initialize logger
logger = setup_logging()


class BatchJob:
    """Main batch job processor."""
    
    def __init__(self):
        """Initialize the batch job with configuration from environment variables."""
        # AWS Batch provided environment variables
        self.job_id = os.getenv('AWS_BATCH_JOB_ID', 'local-job')
        self.job_name = os.getenv('AWS_BATCH_JOB_NAME', 'local-test')
        self.job_queue = os.getenv('AWS_BATCH_JQ_NAME', 'unknown')
        
        # Custom configuration from environment
        self.environment = os.getenv('ENVIRONMENT', 'dev')
        self.project_name = os.getenv('PROJECT_NAME', 'batch-jobs')
        self.aws_region = os.getenv('AWS_REGION', 'us-east-1')
        
        # Job-specific parameters (passed via job submission)
        self.input_path = os.getenv('INPUT_PATH', '')
        self.output_path = os.getenv('OUTPUT_PATH', '')
        self.processing_mode = os.getenv('PROCESSING_MODE', 'standard')
        
        # Initialize AWS clients
        self.s3_client = boto3.client('s3', region_name=self.aws_region)
        self.cloudwatch_client = boto3.client('cloudwatch', region_name=self.aws_region)
        
        # Job metrics
        self.metrics = {
            'records_processed': 0,
            'records_failed': 0,
            'processing_time': 0,
        }
        
        logger.info(
            "Job initialized",
            extra={
                'job_id': self.job_id,
                'job_name': self.job_name,
                'environment': self.environment,
                'processing_mode': self.processing_mode
            }
        )
    
    def validate_configuration(self) -> bool:
        """
        Validate job configuration.
        
        Returns:
            True if configuration is valid, False otherwise
        """
        logger.info("Validating configuration")
        
        required_vars = []
        
        if not self.input_path:
            logger.warning("INPUT_PATH not provided, using default")
        
        if not self.output_path:
            logger.warning("OUTPUT_PATH not provided, will skip output")
        
        # Add your validation logic here
        # For example, check if required secrets/parameters exist
        
        logger.info("Configuration validation complete")
        return True
    
    def load_secrets(self):
        """Load secrets from AWS Secrets Manager (if needed)."""
        logger.info("Loading secrets")
        
        try:
            # Example: Load database credentials
            # db_secret = get_secret(f'{self.project_name}/{self.environment}/database')
            # logger.info("Database credentials loaded")
            
            # Example: Load API keys
            # api_key = get_parameter(f'/{self.project_name}/{self.environment}/api-key')
            # logger.info("API key loaded")
            
            logger.info("All secrets loaded successfully")
        except Exception as e:
            logger.error(f"Error loading secrets: {e}")
            raise
    
    def process_data(self):
        """
        Main data processing logic.
        
        This is where you implement your actual batch job logic.
        """
        logger.info("Starting data processing")
        start_time = datetime.now()
        
        try:
            # Example: Download input data from S3
            if self.input_path:
                logger.info(f"Downloading input from: {self.input_path}")
                # data = download_from_s3(self.input_path)
                # logger.info(f"Downloaded {len(data)} bytes")
            
            # Example: Process data
            logger.info(f"Processing in {self.processing_mode} mode")
            
            # Simulate processing
            import time
            for i in range(10):
                # Your processing logic here
                time.sleep(1)
                self.metrics['records_processed'] += 1
                
                # Log progress
                if (i + 1) % 5 == 0:
                    logger.info(
                        f"Processing progress: {self.metrics['records_processed']} records",
                        extra={'progress': (i + 1) / 10}
                    )
            
            # Example: Upload results to S3
            if self.output_path:
                logger.info(f"Uploading results to: {self.output_path}")
                result_data = {
                    'job_id': self.job_id,
                    'timestamp': datetime.now().isoformat(),
                    'records_processed': self.metrics['records_processed'],
                    'status': 'completed'
                }
                # upload_to_s3(self.output_path, json.dumps(result_data))
                logger.info("Results uploaded successfully")
            
            # Calculate processing time
            end_time = datetime.now()
            self.metrics['processing_time'] = (end_time - start_time).total_seconds()
            
            logger.info(
                "Data processing completed",
                extra={
                    'records_processed': self.metrics['records_processed'],
                    'processing_time': self.metrics['processing_time']
                }
            )
            
        except Exception as e:
            logger.error(f"Error processing data: {e}", exc_info=True)
            raise
    
    def publish_metrics(self):
        """Publish custom metrics to CloudWatch."""
        logger.info("Publishing metrics to CloudWatch")
        
        try:
            # Publish custom metrics
            put_metric(
                'RecordsProcessed',
                self.metrics['records_processed'],
                unit='Count',
                namespace=f'{self.project_name}/BatchJobs'
            )
            
            put_metric(
                'ProcessingTime',
                self.metrics['processing_time'],
                unit='Seconds',
                namespace=f'{self.project_name}/BatchJobs'
            )
            
            logger.info("Metrics published successfully")
            
        except Exception as e:
            logger.warning(f"Error publishing metrics: {e}")
            # Don't fail the job if metrics publishing fails
    
    def cleanup(self):
        """Cleanup resources."""
        logger.info("Cleaning up resources")
        # Add cleanup logic here (temp files, connections, etc.)
    
    def run(self) -> int:
        """
        Execute the batch job.
        
        Returns:
            Exit code (0 for success, non-zero for failure)
        """
        try:
            logger.info(
                "Starting batch job",
                extra={
                    'job_id': self.job_id,
                    'job_name': self.job_name,
                    'timestamp': datetime.now().isoformat()
                }
            )
            
            # Validate configuration
            if not self.validate_configuration():
                logger.error("Configuration validation failed")
                return 1
            
            # Load secrets (if needed)
            # self.load_secrets()
            
            # Process data
            self.process_data()
            
            # Publish metrics
            self.publish_metrics()
            
            # Cleanup
            self.cleanup()
            
            logger.info(
                "Batch job completed successfully",
                extra={
                    'job_id': self.job_id,
                    'metrics': self.metrics,
                    'timestamp': datetime.now().isoformat()
                }
            )
            
            return 0
            
        except Exception as e:
            logger.error(
                f"Batch job failed: {e}",
                exc_info=True,
                extra={
                    'job_id': self.job_id,
                    'timestamp': datetime.now().isoformat()
                }
            )
            return 1


def main():
    """Main entry point."""
    # Create and run job
    job = BatchJob()
    exit_code = job.run()
    
    # Exit with appropriate code
    sys.exit(exit_code)


if __name__ == '__main__':
    main()

