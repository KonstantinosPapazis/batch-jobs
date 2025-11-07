# AWS Batch Migration Guide

## 📋 Table of Contents

1. [Overview](#overview)
2. [Pre-Migration Assessment](#pre-migration-assessment)
3. [Migration Phases](#migration-phases)
4. [Step-by-Step Instructions](#step-by-step-instructions)
5. [Testing Strategy](#testing-strategy)
6. [Rollback Procedure](#rollback-procedure)
7. [Post-Migration Optimization](#post-migration-optimization)
8. [Troubleshooting](#troubleshooting)

## Overview

This guide walks you through migrating on-premise Docker batch jobs to AWS Batch, minimizing downtime and risk.

**Timeline**: 2-4 weeks depending on complexity
**Approach**: Blue-green deployment with gradual migration

## Pre-Migration Assessment

### 1. Inventory Your Current Jobs

Create a spreadsheet of all batch jobs:

| Job Name | Frequency | Duration | CPU | Memory | Dependencies | Input/Output |
|----------|-----------|----------|-----|--------|--------------|--------------|
| data-processor | 1x/day | 30 min | 2 cores | 4GB | PostgreSQL | S3 files |
| report-generator | 2x/day | 15 min | 1 core | 2GB | None | Email |

### 2. Analyze Resource Requirements

For each job, document:
- **CPU requirements**: Average and peak
- **Memory requirements**: Minimum needed
- **Storage**: Disk space, I/O patterns
- **Network**: External dependencies, APIs
- **Duration**: Typical runtime
- **Environment variables**: Configuration needed
- **Secrets**: Database passwords, API keys

### 3. Identify Dependencies

Document:
- Database connections
- API endpoints
- File system dependencies
- Shared volumes
- Service accounts
- Network requirements

### 4. Review Scheduling

Current scheduling mechanism:
- Cron jobs?
- Orchestration tool?
- Manual triggers?
- Event-driven?

## Migration Phases

### Phase 1: Preparation (Week 1)
- ✅ Document current infrastructure
- ✅ Set up AWS account structure
- ✅ Deploy base infrastructure (VPC, networking)
- ✅ Set up ECR repositories
- ✅ Configure monitoring and logging

### Phase 2: Development (Week 1-2)
- ✅ Containerize applications (if not already)
- ✅ Push images to ECR
- ✅ Create AWS Batch job definitions
- ✅ Set up IAM roles and permissions
- ✅ Configure EventBridge schedules

### Phase 3: Testing (Week 2-3)
- ✅ Test jobs in AWS development environment
- ✅ Validate outputs match on-premise results
- ✅ Performance testing
- ✅ Failure scenario testing
- ✅ Cost validation

### Phase 4: Parallel Run (Week 3-4)
- ✅ Run AWS and on-premise in parallel
- ✅ Compare outputs and performance
- ✅ Monitor costs
- ✅ Fine-tune configuration

### Phase 5: Cutover (Week 4)
- ✅ Switch primary execution to AWS
- ✅ Keep on-premise as backup
- ✅ Monitor for 1 week
- ✅ Decommission on-premise infrastructure

## Step-by-Step Instructions

### Step 1: Set Up AWS Infrastructure

#### Option A: Using Terraform

```bash
# Clone this repository
cd terraform

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values:
# - project_name
# - environment
# - aws_region
# - vpc_cidr
nano terraform.tfvars

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the infrastructure
terraform apply
```

#### Option B: Using CloudFormation

```bash
cd cloudformation

# Copy and customize parameters
cp parameters.example.json parameters.json

# Create the stack
aws cloudformation create-stack \
  --stack-name batch-infrastructure \
  --template-body file://batch-stack.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name batch-infrastructure \
  --region us-east-1
```

**What gets created:**
- VPC with public and private subnets
- Internet Gateway and NAT Gateway
- Security Groups
- ECR Repository
- AWS Batch Compute Environment
- AWS Batch Job Queue
- IAM Roles for Batch jobs
- CloudWatch Log Groups
- (Optional) EventBridge rules for scheduling

### Step 2: Prepare Your Docker Images

#### 2.1 Review Your Current Dockerfile

Ensure your Dockerfile follows best practices:

```dockerfile
FROM python:3.11-slim

# Use non-root user for security
RUN useradd -m -u 1000 appuser

# Install dependencies
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Switch to non-root user
USER appuser

# Set entrypoint
ENTRYPOINT ["python", "app.py"]
```

#### 2.2 Add AWS SDK Dependencies

If your job needs to interact with AWS services:

**For Python:**
```txt
# requirements.txt
boto3>=1.28.0
```

**For Node.js:**
```json
{
  "dependencies": {
    "aws-sdk": "^2.1400.0"
  }
}
```

#### 2.3 Handle Environment Variables

Use environment variables for configuration:

```python
import os

# AWS Batch automatically provides some env vars
JOB_ID = os.getenv('AWS_BATCH_JOB_ID', 'local')
JOB_NAME = os.getenv('AWS_BATCH_JOB_NAME', 'unknown')

# Your custom configuration
DATABASE_URL = os.getenv('DATABASE_URL')
S3_BUCKET = os.getenv('S3_BUCKET')
```

#### 2.4 Implement Proper Logging

Use structured logging that works with CloudWatch:

```python
import logging
import json

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Log structured data
logger.info(json.dumps({
    'event': 'job_started',
    'job_id': JOB_ID,
    'timestamp': datetime.now().isoformat()
}))
```

#### 2.5 Handle Secrets Securely

**Option 1: AWS Secrets Manager**

```python
import boto3
import json

def get_secret(secret_name):
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# Usage
db_credentials = get_secret('prod/database/credentials')
```

**Option 2: AWS Systems Manager Parameter Store**

```python
import boto3

def get_parameter(param_name):
    ssm = boto3.client('ssm')
    response = ssm.get_parameter(Name=param_name, WithDecryption=True)
    return response['Parameter']['Value']

# Usage
api_key = get_parameter('/prod/api/key')
```

### Step 3: Build and Push Docker Images to ECR

```bash
# Get your ECR repository URL from Terraform/CloudFormation output
ECR_REPO=$(terraform output -raw ecr_repository_url)
# Or for CloudFormation:
# ECR_REPO=$(aws cloudformation describe-stacks --stack-name batch-infrastructure --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryUrl`].OutputValue' --output text)

AWS_REGION="us-east-1"  # Your region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build your Docker image
cd examples/sample-job  # Or your job directory
docker build -t my-batch-job:latest .

# Tag the image for ECR
docker tag my-batch-job:latest $ECR_REPO:latest
docker tag my-batch-job:latest $ECR_REPO:v1.0.0

# Push to ECR
docker push $ECR_REPO:latest
docker push $ECR_REPO:v1.0.0
```

**Best Practices:**
- Always use version tags (not just `latest`)
- Enable ECR image scanning for vulnerabilities
- Implement image lifecycle policies to clean up old images

### Step 4: Create AWS Batch Job Definitions

#### 4.1 Create Job Definition JSON

```json
{
  "jobDefinitionName": "data-processor-job",
  "type": "container",
  "containerProperties": {
    "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-batch-job:v1.0.0",
    "vcpus": 2,
    "memory": 4096,
    "command": ["python", "process_data.py"],
    "jobRoleArn": "arn:aws:iam::123456789012:role/BatchJobRole",
    "executionRoleArn": "arn:aws:iam::123456789012:role/BatchExecutionRole",
    "environment": [
      {
        "name": "ENVIRONMENT",
        "value": "production"
      },
      {
        "name": "S3_BUCKET",
        "value": "my-data-bucket"
      }
    ],
    "secrets": [
      {
        "name": "DATABASE_PASSWORD",
        "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db/password"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/aws/batch/jobs",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "data-processor"
      }
    },
    "resourceRequirements": []
  },
  "retryStrategy": {
    "attempts": 3,
    "evaluateOnExit": [
      {
        "action": "RETRY",
        "onStatusReason": "Host EC2*"
      },
      {
        "action": "EXIT",
        "onExitCode": "0"
      }
    ]
  },
  "timeout": {
    "attemptDurationSeconds": 3600
  }
}
```

#### 4.2 Register Job Definition

```bash
aws batch register-job-definition --cli-input-json file://job-definition.json
```

#### 4.3 Verify Job Definition

```bash
aws batch describe-job-definitions --job-definition-name data-processor-job
```

### Step 5: Set Up Scheduling with EventBridge

#### 5.1 Create EventBridge Rule

For a job running once per day at 2 AM:

```bash
aws events put-rule \
  --name "daily-data-processor" \
  --schedule-expression "cron(0 2 * * ? *)" \
  --description "Run data processor daily at 2 AM UTC"
```

#### 5.2 Add Batch Job as Target

```bash
aws events put-targets \
  --rule daily-data-processor \
  --targets "Id"="1","Arn"="arn:aws:batch:us-east-1:123456789012:job-queue/default-job-queue","RoleArn"="arn:aws:iam::123456789012:role/EventBridgeBatchRole","BatchParameters"="JobDefinition=data-processor-job,JobName=daily-processor"
```

#### 5.3 Test EventBridge Rule

```bash
# Disable the rule temporarily to avoid conflicts
aws events disable-rule --name daily-data-processor

# Test by submitting a job manually first
aws batch submit-job \
  --job-name "test-run-1" \
  --job-queue default-job-queue \
  --job-definition data-processor-job

# Re-enable after testing
aws events enable-rule --name daily-data-processor
```

### Step 6: Submit Your First Job

#### 6.1 Manual Job Submission

```bash
JOB_ID=$(aws batch submit-job \
  --job-name "manual-test-$(date +%Y%m%d-%H%M%S)" \
  --job-queue default-job-queue \
  --job-definition data-processor-job \
  --query 'jobId' \
  --output text)

echo "Submitted job: $JOB_ID"
```

#### 6.2 Monitor Job Status

```bash
# Check job status
aws batch describe-jobs --jobs $JOB_ID

# Watch job status (poll every 10 seconds)
while true; do
  STATUS=$(aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].status' --output text)
  echo "Job status: $STATUS"
  if [[ "$STATUS" == "SUCCEEDED" || "$STATUS" == "FAILED" ]]; then
    break
  fi
  sleep 10
done
```

#### 6.3 View Job Logs

```bash
# Get log stream name
LOG_STREAM=$(aws batch describe-jobs --jobs $JOB_ID \
  --query 'jobs[0].container.logStreamName' --output text)

# View logs
aws logs tail /aws/batch/jobs --log-stream-names $LOG_STREAM --follow
```

### Step 7: Configure Monitoring and Alerts

#### 7.1 Set Up CloudWatch Alarms

**Job Failure Alarm:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "batch-job-failures" \
  --alarm-description "Alert when batch jobs fail" \
  --metric-name FailedJobs \
  --namespace AWS/Batch \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=JobQueue,Value=default-job-queue \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:batch-alerts
```

**Job Duration Alarm:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "batch-job-long-running" \
  --alarm-description "Alert when jobs run longer than expected" \
  --metric-name RunningJobs \
  --namespace AWS/Batch \
  --statistic Maximum \
  --period 3600 \
  --evaluation-periods 1 \
  --threshold 2 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=JobQueue,Value=default-job-queue \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:batch-alerts
```

#### 7.2 Create CloudWatch Dashboard

```bash
# Create a dashboard definition
cat > dashboard.json << 'EOF'
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Batch", "SubmittedJobs"],
          [".", "RunningJobs"],
          [".", "SucceededJobs"],
          [".", "FailedJobs"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "Batch Job Metrics"
      }
    }
  ]
}
EOF

aws cloudwatch put-dashboard \
  --dashboard-name batch-monitoring \
  --dashboard-body file://dashboard.json
```

## Testing Strategy

### 1. Unit Testing (Local)

Test Docker containers locally before deploying:

```bash
# Run container locally with test data
docker run --rm \
  -e ENVIRONMENT=test \
  -e S3_BUCKET=test-bucket \
  my-batch-job:latest
```

### 2. Integration Testing (AWS Dev Environment)

```bash
# Submit test job to dev environment
aws batch submit-job \
  --job-name "integration-test-$(date +%s)" \
  --job-queue dev-job-queue \
  --job-definition data-processor-job:1
```

**Test Scenarios:**
- ✅ Normal execution with valid inputs
- ✅ Invalid input handling
- ✅ Network failure scenarios
- ✅ Timeout scenarios
- ✅ Retry logic
- ✅ Resource exhaustion (memory, CPU)

### 3. Performance Testing

Compare performance metrics:

| Metric | On-Premise | AWS Batch | Difference |
|--------|------------|-----------|------------|
| Execution Time | 30 min | 28 min | -6.7% |
| CPU Utilization | 85% | 75% | -10% |
| Memory Peak | 3.8GB | 3.5GB | -7.9% |
| Cost per Run | $0.50 | $0.15 | -70% |

### 4. Parallel Run Validation

Run both systems in parallel for 1-2 weeks:

```bash
#!/bin/bash
# Compare outputs between on-premise and AWS

ON_PREM_OUTPUT="s3://bucket/on-prem/output.csv"
AWS_OUTPUT="s3://bucket/aws/output.csv"

# Download both
aws s3 cp $ON_PREM_OUTPUT /tmp/on-prem.csv
aws s3 cp $AWS_OUTPUT /tmp/aws.csv

# Compare
if diff /tmp/on-prem.csv /tmp/aws.csv; then
  echo "✅ Outputs match!"
else
  echo "❌ Outputs differ!"
  exit 1
fi
```

## Rollback Procedure

### Emergency Rollback Checklist

If critical issues arise:

1. **Immediate Actions (< 5 minutes)**
   ```bash
   # Disable EventBridge rule to stop new jobs
   aws events disable-rule --name daily-data-processor
   
   # Cancel running jobs if necessary
   aws batch cancel-job --job-id <job-id> --reason "Rollback to on-premise"
   ```

2. **Re-enable On-Premise System (< 15 minutes)**
   - Start on-premise Docker containers
   - Re-enable cron jobs
   - Verify functionality

3. **Root Cause Analysis (< 24 hours)**
   - Review CloudWatch logs
   - Analyze job failures
   - Document issues

4. **Fix and Re-test (< 1 week)**
   - Address identified issues
   - Test in dev environment
   - Retry migration

### Rollback Decision Criteria

Rollback if:
- ❌ Job failure rate > 5%
- ❌ Performance degradation > 20%
- ❌ Data integrity issues
- ❌ Costs exceed budget by > 50%
- ❌ Critical bugs in production

Continue if:
- ✅ Minor issues with workarounds
- ✅ Performance within acceptable range
- ✅ Costs within budget
- ✅ No data integrity issues

## Post-Migration Optimization

### 1. Right-Size Resources

After 1-2 weeks, analyze actual usage:

```bash
# Get average vCPU usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/Batch \
  --metric-name CPUUtilization \
  --dimensions Name=JobId,Value=<job-id> \
  --start-time 2025-11-01T00:00:00Z \
  --end-time 2025-11-07T00:00:00Z \
  --period 3600 \
  --statistics Average
```

Adjust job definition based on findings:
- Reduce vCPUs if average usage < 50%
- Reduce memory if peak usage < 70%
- Consider spot instances for non-critical jobs

### 2. Implement Cost Optimization

**Use Spot Instances:**

```hcl
# In Terraform, modify compute environment
compute_resources {
  type = "SPOT"
  bid_percentage = 80  # Bid 80% of on-demand price
  spot_iam_fleet_role = aws_iam_role.spot_fleet_role.arn
}
```

**Implement Auto-Scaling:**

```hcl
compute_resources {
  min_vcpus = 0     # Scale to zero when idle
  max_vcpus = 256
  desired_vcpus = 0
}
```

### 3. Optimize Docker Images

- Use multi-stage builds to reduce image size
- Remove unnecessary dependencies
- Use Alpine base images where possible
- Implement layer caching

```dockerfile
# Multi-stage build example
FROM python:3.11 AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

FROM python:3.11-slim
COPY --from=builder /root/.local /root/.local
COPY . /app
WORKDIR /app
ENV PATH=/root/.local/bin:$PATH
ENTRYPOINT ["python", "app.py"]
```

### 4. Implement Advanced Monitoring

**Custom CloudWatch Metrics:**

```python
import boto3

cloudwatch = boto3.client('cloudwatch')

def put_metric(metric_name, value, unit='Count'):
    cloudwatch.put_metric_data(
        Namespace='CustomBatch',
        MetricData=[
            {
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit
            }
        ]
    )

# Usage in your job
put_metric('RecordsProcessed', 10000, 'Count')
put_metric('ProcessingTime', 125.5, 'Seconds')
```

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: Job Stuck in RUNNABLE State

**Symptoms:** Job remains in RUNNABLE for extended period

**Causes:**
- Insufficient compute resources
- EC2 capacity issues
- AMI not available in all AZs

**Solutions:**
```bash
# Check compute environment status
aws batch describe-compute-environments \
  --compute-environments default-compute-env

# Increase max vCPUs if needed
aws batch update-compute-environment \
  --compute-environment default-compute-env \
  --compute-resources maxvCpus=256

# Check for EC2 capacity issues in CloudWatch logs
```

#### Issue 2: Job Fails with Exit Code 137 (OOM)

**Symptoms:** Job terminated with exit code 137

**Cause:** Out of memory

**Solution:**
```bash
# Increase memory in job definition
aws batch register-job-definition \
  --job-definition-name my-job \
  --type container \
  --container-properties memory=8192  # Increased from 4096
```

#### Issue 3: Cannot Pull Docker Image

**Symptoms:** `CannotPullContainerError`

**Causes:**
- IAM permissions missing
- ECR repository policy issues
- Image doesn't exist

**Solutions:**
```bash
# Verify execution role has ECR permissions
aws iam get-role-policy \
  --role-name BatchExecutionRole \
  --policy-name ECRAccessPolicy

# Test image pull manually
aws ecr get-login-password | docker login --username AWS --password-stdin <ecr-url>
docker pull <ecr-url>/<image>:<tag>
```

#### Issue 4: Job Timeout

**Symptoms:** Job terminated due to timeout

**Solution:**
```bash
# Increase timeout in job definition
aws batch register-job-definition \
  --job-definition-name my-job \
  --type container \
  --timeout attemptDurationSeconds=7200  # 2 hours
```

#### Issue 5: Networking Issues

**Symptoms:** Cannot connect to databases, APIs, or S3

**Causes:**
- Security group rules
- No NAT Gateway for private subnets
- VPC endpoint configuration

**Solutions:**
```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids <sg-id>

# Verify NAT Gateway exists
aws ec2 describe-nat-gateways

# Add VPC endpoint for S3 (reduces costs and latency)
aws ec2 create-vpc-endpoint \
  --vpc-id <vpc-id> \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids <route-table-id>
```

### Debugging Tips

1. **Enable DEBUG logging in your application**
2. **Use CloudWatch Logs Insights for analysis**
3. **Test with smaller datasets first**
4. **Run jobs manually before enabling scheduling**
5. **Keep on-premise system available during initial period**

### Getting Help

- AWS Batch Documentation: https://docs.aws.amazon.com/batch/
- AWS Support: Create a support ticket
- Internal team: [Your team's contact info]

## Next Steps

After successful migration:

1. ✅ Monitor costs daily for first week
2. ✅ Document any custom configurations
3. ✅ Train team on new workflow
4. ✅ Set up backup and disaster recovery
5. ✅ Plan decommissioning of on-premise infrastructure
6. ✅ Consider expanding to other batch workloads

## Appendix

### A. Useful AWS CLI Commands

```bash
# List all job queues
aws batch describe-job-queues

# List all compute environments
aws batch describe-compute-environments

# List recent jobs
aws batch list-jobs --job-queue default-job-queue --job-status SUCCEEDED

# Get job details
aws batch describe-jobs --jobs <job-id>

# Terminate a job
aws batch terminate-job --job-id <job-id> --reason "Manual termination"

# List ECR images
aws ecr describe-images --repository-name my-batch-job
```

### B. Sample Job Definition Templates

See `examples/job-definitions/` directory for various templates.

### C. Cost Tracking Query

```sql
-- CloudWatch Logs Insights query for cost analysis
fields @timestamp, jobId, vcpus, memory, duration
| filter jobStatus = "SUCCEEDED"
| stats sum(duration) as totalDuration, avg(vcpus) as avgCPU by jobName
| sort totalDuration desc
```

---

**Document Version:** 1.0  
**Last Updated:** November 2025  
**Maintained By:** DevOps Team

