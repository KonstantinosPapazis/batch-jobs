# AWS Batch with Fargate - Terraform Configuration

This directory contains a **Fargate-specific** Terraform configuration for AWS Batch. This is a complete, standalone setup optimized for serverless batch processing with Fargate.

## 🆚 EC2 vs Fargate: Which Should You Choose?

### Use Fargate (This Folder) If:
- ✅ You want **zero infrastructure management**
- ✅ Jobs are **sporadic or unpredictable**
- ✅ You value **simplicity over cost**
- ✅ **Fast cold starts** (30-60s) are important
- ✅ You don't need spot instances

### Use EC2 (`../terraform/`) If:
- ✅ Running jobs **regularly** (like 1-2x/day)
- ✅ Want **maximum cost optimization** (spot = 60-70% savings)
- ✅ Need **specific instance types or GPUs**
- ✅ Have **consistent workload patterns**

## 💰 Cost Comparison (2 jobs/day, 30 min each)

| Configuration | Monthly Cost | Notes |
|---------------|--------------|-------|
| **Fargate** | **$4-15** | Simple, serverless |
| EC2 On-Demand | $25-40 | More control |
| **EC2 Spot** | **$3-10** | 💰 Cheapest |

**For your use case (1-2 jobs/day):** EC2 Spot is more cost-effective, but Fargate is simpler.

## 📋 Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured
- Terraform >= 1.0
- Docker installed

## 🚀 Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Key settings for Fargate:
```hcl
# Network (IMPORTANT for Fargate)
enable_vpc_endpoints = true   # Recommended (saves money)
enable_nat_gateway   = false  # Not needed with VPC endpoints

# Fargate Resources
default_job_vcpu   = "0.25"  # Valid: 0.25, 0.5, 1, 2, 4
default_job_memory = "512"   # Must match vCPU (see docs)
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 3. Build and Push Docker Image

```bash
# Get ECR URL
ECR_REPO=$(terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_REPO

# Build and push (using example from parent directory)
cd ../examples/sample-job
docker build -t batch-job-fargate:latest .
docker tag batch-job-fargate:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
```

### 4. Submit Test Job

```bash
# Get queue and job definition names
JOB_QUEUE=$(terraform output -raw batch_job_queue_name)
SMALL_JOB=$(terraform output -raw small_job_definition_name)

# Submit small job (0.25 vCPU, 512 MB)
aws batch submit-job \
  --job-name "fargate-test-$(date +%s)" \
  --job-queue $JOB_QUEUE \
  --job-definition $SMALL_JOB
```

### 5. Monitor Job

```bash
# View logs
aws logs tail /aws/batch/batch-jobs-prod-fargate --follow
```

## 📊 Fargate Resource Combinations

Fargate requires specific vCPU/memory combinations:

| vCPU | Memory Options (MB) | Use Case |
|------|---------------------|----------|
| 0.25 | 512, 1024, 2048 | Tiny jobs |
| 0.5  | 1024-4096 | Small jobs |
| 1    | 2048-8192 | Medium jobs |
| 2    | 4096-16384 | Large jobs |
| 4    | 8192-30720 | Very large jobs |

**Example Job Definitions Included:**
- **Small**: 0.25 vCPU, 512 MB (cheapest)
- **Medium**: 0.5 vCPU, 1024 MB
- **Large**: 1 vCPU, 2048 MB

## 🏗️ What Gets Created

### Networking
- VPC with public/private subnets (2 AZs)
- **VPC Endpoints** for ECR, S3, CloudWatch (recommended)
- Optional NAT Gateway (if VPC endpoints disabled)
- Security groups for Fargate tasks

### AWS Batch
- **Fargate compute environment** (serverless)
- Job queue with priority support
- 3 job definitions (small, medium, large)
- CloudWatch log groups

### IAM Roles
- Batch service role
- Execution role (for pulling images)
- Job role (for S3, Secrets Manager access)
- EventBridge role (for scheduling)

### Container Registry
- ECR repository with:
  - Image scanning enabled
  - Lifecycle policies
  - Encryption at rest

### Monitoring
- CloudWatch logs (30-day retention)
- CloudWatch alarms for failures
- SNS topic for alerts (optional)

## 🔧 Configuration Options

### Network Configuration

**Option 1: VPC Endpoints (Recommended)**
```hcl
enable_vpc_endpoints = true
enable_nat_gateway   = false
# Cost: ~$21/month for endpoints
# Benefit: Faster, more secure, no data transfer charges
```

**Option 2: NAT Gateway**
```hcl
enable_vpc_endpoints = false
enable_nat_gateway   = true
# Cost: ~$32/month + data transfer
# Use only if VPC endpoints don't work for your use case
```

**⚠️ Important:** Fargate needs **either** VPC endpoints **or** NAT Gateway to pull ECR images!

### Job Resources

Create custom job definitions with different sizes:

```hcl
# In your own .tf file
resource "aws_batch_job_definition" "custom" {
  name = "my-custom-job"
  type = "container"
  
  platform_capabilities = ["FARGATE"]
  
  container_properties = jsonencode({
    image = aws_ecr_repository.batch_jobs.repository_url
    
    resourceRequirements = [
      { type = "VCPU", value = "1" },
      { type = "MEMORY", value = "2048" }
    ]
    
    # ... other properties
  })
}
```

### Scheduling

Enable scheduled jobs:

```hcl
enable_eventbridge_schedule = true
schedule_expression         = "cron(0 2 * * ? *)"  # Daily at 2 AM
schedule_job_definition     = ""  # Uses small job by default
```

## 📈 Monitoring

### CloudWatch Logs

```bash
# Tail logs in real-time
aws logs tail /aws/batch/batch-jobs-prod-fargate --follow

# View specific job
aws logs get-log-events \
  --log-group-name /aws/batch/batch-jobs-prod-fargate \
  --log-stream-name small-job/default/abc123
```

### Job Status

```bash
# List recent jobs
aws batch list-jobs \
  --job-queue $(terraform output -raw batch_job_queue_name) \
  --job-status SUCCEEDED

# Describe specific job
aws batch describe-jobs --jobs <job-id>
```

### Metrics

Available in CloudWatch console:
- `AWS/Batch` namespace
- Metrics: SubmittedJobs, RunningJobs, SucceededJobs, FailedJobs

## 🔐 Security

- ✅ Fargate tasks run in **private subnets**
- ✅ Security groups with **minimal permissions**
- ✅ IAM roles follow **least privilege**
- ✅ ECR images **encrypted at rest**
- ✅ CloudWatch logs **encrypted**
- ✅ **Non-root containers** (in Dockerfile)
- ✅ **Image scanning** enabled

## 💡 Tips & Best Practices

### 1. Start Small
- Begin with 0.25 vCPU jobs
- Scale up only if needed
- Monitor actual resource usage

### 2. Use VPC Endpoints
- Cheaper than NAT Gateway
- Faster image pulls
- More secure (no internet route)

### 3. Right-Size Resources
- Don't over-provision vCPU/memory
- Use CloudWatch metrics to optimize
- Fargate charges per vCPU-second and GB-second

### 4. Implement Retries
- Fargate tasks can fail to start
- Always configure retry strategy
- Use exponential backoff

### 5. Monitor Costs
- Enable cost allocation tags
- Set up billing alerts
- Review Cost Explorer weekly

## 🐛 Troubleshooting

### Issue: Task fails to start

**Error:** `CannotPullContainerError`

**Solution:**
```bash
# Ensure VPC endpoints OR NAT Gateway enabled
# Verify execution role has ECR permissions
aws iam get-role-policy --role-name <execution-role> --policy-name ECRAccess

# Test image exists
aws ecr describe-images --repository-name batch-jobs-fargate
```

### Issue: Invalid CPU/memory combination

**Error:** `ResourceRequirement error`

**Solution:** Use valid combinations:
- 0.25 vCPU: 512, 1024, 2048 MB only
- 0.5 vCPU: 1024, 2048, 3072, 4096 MB only
- See full table above

### Issue: Job never leaves RUNNABLE state

**Possible causes:**
- Max vCPUs reached
- No subnets available
- Security group misconfiguration

**Solution:**
```bash
# Check compute environment
aws batch describe-compute-environments

# Increase max vCPUs
# Edit terraform.tfvars: max_vcpus = 512
terraform apply
```

## 📚 Additional Resources

- [AWS Batch with Fargate Documentation](https://docs.aws.amazon.com/batch/latest/userguide/fargate.html)
- [Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
- [Valid CPU/Memory Combinations](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html)

## 🧹 Cleanup

To remove all resources:

```bash
terraform destroy
```

**⚠️ Warning:** This will delete everything and cannot be undone!

## 🔄 Switching from EC2 to Fargate

Already deployed with EC2? Here's how to switch:

1. **Deploy Fargate stack** (this folder)
2. **Test jobs** on Fargate
3. **Update schedulers** to use new queue
4. **Destroy EC2 stack** when confident

Both can run in parallel during testing!

---

**Need help?** Check the main [Migration Guide](../docs/MIGRATION_GUIDE.md) or [Cost Comparison](../docs/COST_COMPARISON.md).

