# Quick Start Guide

Get your AWS Batch infrastructure up and running in 15 minutes!

## 📋 Prerequisites

Before starting, ensure you have:

- ✅ AWS Account with appropriate permissions
- ✅ AWS CLI installed and configured (`aws configure`)
- ✅ Docker installed locally
- ✅ Terraform >= 1.0 OR CloudFormation (choose one)
- ✅ Git (to clone this repository)

## 🚀 Option 1: Quick Deploy with Terraform (Recommended)

### Step 1: Configure Variables (2 minutes)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your preferences:
```hcl
project_name = "batch-jobs"
environment  = "prod"
aws_region   = "us-east-1"

# Cost optimization settings
enable_nat_gateway   = false    # Save ~$32/month
enable_vpc_endpoints = true     # Use VPC endpoints instead
compute_type         = "SPOT"   # Save 60-70% on compute
```

### Step 2: Deploy Infrastructure (5 minutes)

```bash
./scripts/deploy.sh terraform
```

This will:
- ✅ Create VPC and networking
- ✅ Set up AWS Batch compute environment
- ✅ Create ECR repository
- ✅ Configure IAM roles
- ✅ Set up CloudWatch logging

### Step 3: Build and Push Docker Image (3 minutes)

```bash
./scripts/deploy.sh build-push
```

Or manually:
```bash
cd examples/sample-job

# Get ECR URL from Terraform output
ECR_REPO=$(cd ../../terraform && terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_REPO

# Build and push
docker build -t batch-job:latest .
docker tag batch-job:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
```

### Step 4: Submit Test Job (2 minutes)

```bash
./scripts/deploy.sh test
```

Or manually:
```bash
cd terraform
JOB_QUEUE=$(terraform output -raw batch_job_queue_name)
JOB_DEF=$(terraform output -raw example_job_definition_name)

aws batch submit-job \
  --job-name "test-$(date +%s)" \
  --job-queue $JOB_QUEUE \
  --job-definition $JOB_DEF
```

### Step 5: Monitor Your Job

```bash
# Get job ID from previous command output
JOB_ID="your-job-id"

# Check status
aws batch describe-jobs --jobs $JOB_ID

# View logs
aws logs tail /aws/batch/batch-jobs-prod --follow
```

**🎉 Done! Your first batch job is running on AWS!**

---

## 🚀 Option 2: Quick Deploy with CloudFormation

### Step 1: Configure Parameters (2 minutes)

```bash
cd cloudformation
cp parameters.example.json parameters.json
```

Edit `parameters.json` with your values:
```json
[
  {
    "ParameterKey": "ProjectName",
    "ParameterValue": "batch-jobs"
  },
  {
    "ParameterKey": "Environment",
    "ParameterValue": "prod"
  },
  {
    "ParameterKey": "ComputeType",
    "ParameterValue": "SPOT"
  }
]
```

### Step 2: Deploy Stack (5 minutes)

```bash
./scripts/deploy.sh cloudformation
```

Or manually:
```bash
aws cloudformation create-stack \
  --stack-name batch-jobs-prod \
  --template-body file://batch-stack.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name batch-jobs-prod
```

### Step 3: Build and Push Docker Image (3 minutes)

```bash
./scripts/deploy.sh build-push
```

### Step 4: Submit Test Job (2 minutes)

```bash
./scripts/deploy.sh test
```

---

## 💰 Calculate Your Costs

Use the cost calculator to estimate your monthly spend:

```bash
cd cost-analysis

# For default configuration (2 jobs/day, 30 min each)
python calculator.py --jobs 2 --duration 30 --vcpu 2 --memory 4096

# For higher frequency
python calculator.py --jobs 10 --duration 60 --vcpu 4 --memory 8192

# With on-demand instances (no spot)
python calculator.py --jobs 2 --duration 30 --no-spot
```

**Expected costs for 2 jobs/day:**
- **With Spot instances:** $15-25/month 💰
- **On-demand instances:** $40-50/month
- **Savings vs on-premise:** ~$350-380/month

---

## 📅 Set Up Scheduled Jobs

### Option 1: Using Terraform Variables

Edit `terraform.tfvars`:
```hcl
enable_eventbridge_schedule = true
schedule_expression         = "cron(0 2 * * ? *)"  # Daily at 2 AM
```

Apply changes:
```bash
cd terraform
terraform apply
```

### Option 2: Using AWS CLI

```bash
# Create schedule rule
aws events put-rule \
  --name "daily-batch-job" \
  --schedule-expression "cron(0 2 * * ? *)"

# Add Batch job as target
aws events put-targets \
  --rule daily-batch-job \
  --targets "Id=1,Arn=arn:aws:batch:us-east-1:123456789012:job-queue/my-queue,RoleArn=arn:aws:iam::123456789012:role/EventBridgeBatchRole,BatchParameters={JobDefinition=my-job,JobName=scheduled-job}"
```

### Common Schedules

| Schedule | Expression |
|----------|------------|
| Every day at 2 AM UTC | `cron(0 2 * * ? *)` |
| Twice daily (2 AM & 2 PM) | `cron(0 2,14 * * ? *)` |
| Every hour | `rate(1 hour)` |
| Every 30 minutes | `rate(30 minutes)` |
| Weekdays at 9 AM | `cron(0 9 ? * MON-FRI *)` |
| Every Monday at 3 AM | `cron(0 3 ? * MON *)` |

---

## 🔧 Customize Your Job

### 1. Modify the Application

Edit `examples/sample-job/app.py` with your logic:

```python
def process_data(self):
    # Your custom processing logic here
    logger.info("Processing data...")
    
    # Example: Download from S3
    data = download_from_s3(self.input_path)
    
    # Example: Process data
    result = your_processing_function(data)
    
    # Example: Upload to S3
    upload_to_s3(self.output_path, result)
```

### 2. Update Dependencies

Edit `examples/sample-job/requirements.txt`:
```txt
boto3>=1.28.0
pandas>=2.0.0
numpy>=1.24.0
# Add your dependencies here
```

### 3. Rebuild and Push

```bash
./scripts/deploy.sh build-push v1.0.1
```

### 4. Create Custom Job Definition

Create `my-custom-job.json`:
```json
{
  "jobDefinitionName": "my-custom-job",
  "type": "container",
  "containerProperties": {
    "image": "YOUR_ECR_REPO:v1.0.1",
    "resourceRequirements": [
      {"type": "VCPU", "value": "2"},
      {"type": "MEMORY", "value": "4096"}
    ],
    "environment": [
      {"name": "INPUT_PATH", "value": "s3://my-bucket/input"},
      {"name": "OUTPUT_PATH", "value": "s3://my-bucket/output"}
    ]
  }
}
```

Register it:
```bash
aws batch register-job-definition --cli-input-json file://my-custom-job.json
```

---

## 🎯 Next Steps

### For Development
1. ✅ Read [Migration Guide](docs/MIGRATION_GUIDE.md)
2. ✅ Review [Architecture](docs/ARCHITECTURE.md)
3. ✅ Check [Cost Comparison](docs/COST_COMPARISON.md)
4. ✅ Customize job definitions
5. ✅ Set up monitoring and alerts

### For Production
1. ✅ Enable EventBridge scheduling
2. ✅ Set up CloudWatch alarms
3. ✅ Configure SNS notifications
4. ✅ Implement backup strategy
5. ✅ Document runbooks

### Optimization
1. ✅ Monitor actual costs in Cost Explorer
2. ✅ Right-size resources based on metrics
3. ✅ Enable VPC endpoints (save $15-20/month)
4. ✅ Use Spot instances (save 60-70%)
5. ✅ Implement log retention policies

---

## 🐛 Troubleshooting

### Job stuck in RUNNABLE
**Problem:** Job not starting

**Solutions:**
```bash
# Check compute environment status
aws batch describe-compute-environments --compute-environments my-env

# Increase max vCPUs if needed
cd terraform
# Edit terraform.tfvars: max_vcpus = 512
terraform apply
```

### Cannot pull Docker image
**Problem:** `CannotPullContainerError`

**Solutions:**
```bash
# Verify image exists in ECR
aws ecr describe-images --repository-name batch-jobs

# Check IAM permissions
aws iam get-role-policy --role-name BatchExecutionRole --policy-name ECRAccess

# Test image pull manually
aws ecr get-login-password | docker login --username AWS --password-stdin YOUR_ECR_URL
docker pull YOUR_ECR_URL:latest
```

### Job fails immediately
**Problem:** Exit code 1 or container error

**Solutions:**
```bash
# View logs
aws logs tail /aws/batch/batch-jobs-prod --follow

# Test container locally
docker run --rm -e ENVIRONMENT=dev YOUR_IMAGE:latest

# Check job definition
aws batch describe-job-definitions --job-definition-name my-job
```

---

## 📞 Get Help

- 📖 [Full Documentation](docs/MIGRATION_GUIDE.md)
- 🏗️ [Architecture Details](docs/ARCHITECTURE.md)
- 💰 [Cost Analysis](docs/COST_COMPARISON.md)
- 🔍 [AWS Batch Docs](https://docs.aws.amazon.com/batch/)

---

## 🧹 Cleanup (When Done Testing)

To remove all resources:

```bash
# Using scripts
./scripts/cleanup.sh terraform
# or
./scripts/cleanup.sh cloudformation

# Or manually
cd terraform
terraform destroy

# Or CloudFormation
aws cloudformation delete-stack --stack-name batch-jobs-prod
```

**⚠️ Warning:** This will delete all resources and cannot be undone!

---

**Ready to migrate your production workloads?** Check out the [Migration Guide](docs/MIGRATION_GUIDE.md) for a detailed step-by-step process!

