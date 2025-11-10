# Production AWS Batch with Fargate - Data Science Team
## Using External Nexus Registry

This is a **production-ready** Terraform configuration for running your data science team's cron jobs on AWS Batch with Fargate, pulling images from your Nexus registry.

## 📋 What This Deploys

### Infrastructure
- ✅ VPC with public/private subnets (multi-AZ)
- ✅ VPC Endpoints (ECR, CloudWatch, S3) - saves NAT costs
- ✅ AWS Batch compute environment (Fargate)
- ✅ Job queue with proper configuration
- ✅ IAM roles (scoped to data science team)
- ✅ CloudWatch logs (30-day retention)
- ✅ EventBridge rule (runs daily at 2 AM UTC)
- ✅ CloudWatch alarms for failures
- ✅ SNS topic for alerts

### What's NOT Included
- ❌ ECR repository (you use Nexus)
- ❌ NAT Gateway (using VPC endpoints instead)

## 🚀 Quick Start

### Prerequisites

1. **Nexus Registry Access**
   - Nexus URL (e.g., `nexus.company.com:5000`)
   - Username and password
   - Image path (e.g., `nexus.company.com:5000/datascience/job-name:latest`)

2. **AWS Prerequisites**
   - AWS account with admin access
   - AWS CLI configured: `aws configure`
   - Terraform >= 1.0 installed

### Step 1: Store Nexus Credentials in AWS Secrets Manager

```bash
# Create secret for Nexus credentials
aws secretsmanager create-secret \
  --name batch-jobs/datascience/nexus-credentials \
  --description "Nexus registry credentials for data science team" \
  --secret-string '{
    "username": "your-nexus-username",
    "password": "your-nexus-password",
    "registry": "nexus.company.com:5000"
  }' \
  --region us-east-1
```

### Step 2: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

**Required changes:**
- `nexus_registry_url` - Your Nexus URL
- `nexus_secret_arn` - Secret ARN from Step 1
- `container_image` - Full image path
- `alert_email` - Your email for alerts

### Step 3: Deploy

```bash
# Initialize Terraform
terraform init

# Review what will be created
terraform plan

# Deploy to production
terraform apply
```

**Deployment time:** ~10 minutes

### Step 4: Verify

```bash
# Check if EventBridge rule is enabled
aws events describe-rule --name batch-jobs-datascience-prod-daily-job

# Manually trigger a test run
aws batch submit-job \
  --job-name "manual-test-$(date +%s)" \
  --job-queue $(terraform output -raw job_queue_name) \
  --job-definition $(terraform output -raw job_definition_name)

# Watch logs in real-time
aws logs tail $(terraform output -raw log_group_name) --follow
```

## 🔐 Security Features

### Network Security
- ✅ Private subnets only (no direct internet access)
- ✅ VPC endpoints for AWS services (no NAT Gateway needed)
- ✅ Security groups with minimal permissions
- ✅ No public IP addresses on tasks

### IAM Security
- ✅ Separate execution and job roles
- ✅ Scoped to data science team resources only
- ✅ Secrets Manager access for Nexus credentials
- ✅ Least privilege principle

### Data Security
- ✅ Nexus credentials encrypted in Secrets Manager
- ✅ CloudWatch logs encrypted at rest
- ✅ S3 access scoped to team buckets

## 📊 Cost Estimate

For **1 job per day, 30 minutes execution**:

| Component | Monthly Cost | Notes |
|-----------|--------------|-------|
| Fargate (0.25 vCPU, 512MB) | $1.21 | 30 hrs × $0.04/hr |
| VPC Endpoints | $21.00 | 3 endpoints × $7/mo |
| CloudWatch Logs | $2.50 | 5 GB/month |
| S3 Storage | $2.30 | 100 GB |
| **Total** | **~$27/month** | |

**Compared to on-premise server:** Save ~$200-300/month! 💰

## 📅 Schedule Configuration

Default: **Daily at 2 AM UTC**

To change the schedule, edit `terraform.tfvars`:

```hcl
schedule_expression = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC

# Other examples:
# Twice daily:        "cron(0 2,14 * * ? *)"
# Every 6 hours:      "rate(6 hours)"
# Weekdays at 9 AM:   "cron(0 9 ? * MON-FRI *)"
# First of month:     "cron(0 2 1 * ? *)"
```

**Time zones:** EventBridge uses UTC. To run at 2 AM EST (UTC-5):
```hcl
schedule_expression = "cron(0 7 * * ? *)"  # 2 AM EST = 7 AM UTC
```

## 🔧 Customization

### Adding More Jobs

Each cron job from your on-premise server should become a separate job definition:

```hcl
# In main.tf, add more job definitions
module "daily_report_job" {
  source = "./modules/batch-job-definition"
  
  job_name        = "daily-report"
  container_image = "nexus.company.com:5000/datascience/daily-report:latest"
  schedule        = "cron(0 2 * * ? *)"
  vcpu            = "0.25"
  memory          = "512"
}

module "weekly_analysis_job" {
  source = "./modules/batch-job-definition"
  
  job_name        = "weekly-analysis"
  container_image = "nexus.company.com:5000/datascience/weekly-analysis:latest"
  schedule        = "cron(0 3 ? * MON *)"  # Mondays at 3 AM
  vcpu            = "0.5"
  memory          = "1024"
}
```

### Adjusting Resources

If your jobs need more resources:

```hcl
# In terraform.tfvars
task_vcpu   = "1"      # More CPU
task_memory = "2048"   # More memory (must match Fargate combinations)
```

**Valid Fargate combinations:**
- 0.25 vCPU: 512, 1024, 2048 MB
- 0.5 vCPU: 1024-4096 MB
- 1 vCPU: 2048-8192 MB
- 2 vCPU: 4096-16384 MB

### Environment Variables

Add environment variables to your job:

```hcl
# In main.tf, job definition environment block
environment = [
  { name = "ENVIRONMENT", value = "production" },
  { name = "DATA_BUCKET", value = "s3://datascience-prod" },
  { name = "LOG_LEVEL", value = "INFO" }
]
```

## 🐛 Troubleshooting

### Job fails to pull image from Nexus

**Symptoms:** `CannotPullContainerError`

**Solutions:**
1. Verify Nexus credentials in Secrets Manager:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id batch-jobs/datascience/nexus-credentials
   ```

2. Test Nexus connectivity from your VPC:
   ```bash
   # Ensure your VPC can reach Nexus
   # May need VPC peering or VPN if Nexus is on-premise
   ```

3. Check image path is correct:
   ```bash
   # Full path should be:
   nexus.company.com:5000/datascience/your-job:latest
   ```

### Job never starts (stuck in RUNNABLE)

**Cause:** No compute capacity

**Solution:**
```bash
# Check compute environment
aws batch describe-compute-environments \
  --compute-environments batch-jobs-datascience-prod-fargate-compute-env

# Increase max vCPUs if needed
# Edit terraform.tfvars: max_vcpus = 512
terraform apply
```

### Job runs but fails immediately

**Check logs:**
```bash
# View recent logs
aws logs tail /aws/batch/batch-jobs-datascience-prod --follow

# Or in AWS Console:
# CloudWatch > Log Groups > /aws/batch/batch-jobs-datascience-prod
```

### Nexus is on-premise - can't connect

**You need network connectivity:**

**Option A: VPN Connection**
```
Your VPC <--VPN--> On-Premise Network <--> Nexus
```

**Option B: AWS Direct Connect**
```
Your VPC <--Direct Connect--> On-Premise <--> Nexus
```

**Option C: Migrate to AWS ECR** (recommended)
```bash
# Copy images from Nexus to ECR
docker pull nexus.company.com:5000/datascience/job:latest
docker tag nexus.company.com:5000/datascience/job:latest \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/datascience/job:latest
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/datascience/job:latest
```

## 📧 Monitoring & Alerts

### CloudWatch Alarms

Automatically created alarms:
- ✅ Job failures (notifies via SNS/email)
- ✅ No jobs running when expected

### Email Notifications

Configure in `terraform.tfvars`:
```hcl
alert_email = "datascience-team@company.com"
```

You'll receive:
- Job failure notifications
- Job timeout alerts
- Compute environment issues

### Dashboard

View in AWS Console:
1. Go to CloudWatch > Dashboards
2. Look for: `batch-jobs-datascience-prod-dashboard`

Metrics shown:
- Jobs submitted
- Jobs succeeded
- Jobs failed
- Execution time

## 🔄 CI/CD Integration

### Updating Container Images

When you update images in Nexus:

**Option 1: Use `:latest` tag** (easiest)
- No Terraform changes needed
- Next scheduled run picks up new image automatically

**Option 2: Version tags** (recommended for production)
```hcl
# Update terraform.tfvars
container_image = "nexus.company.com:5000/datascience/job:v2.0.0"

# Deploy
terraform apply
```

### Automated Deployment

**GitHub Actions example:**
```yaml
name: Update Batch Job
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Apply
        run: |
          cd production-fargate-nexus
          terraform init
          terraform apply -auto-approve
```

## 📚 Additional Documentation

- [AWS Batch with Fargate](https://docs.aws.amazon.com/batch/latest/userguide/fargate.html)
- [EventBridge Schedules](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html)
- [Fargate Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)

## 🆘 Support

### Common Issues

| Issue | Solution |
|-------|----------|
| Can't reach Nexus | Check VPN/Direct Connect |
| Job fails on schedule | Check CloudWatch logs |
| Too expensive | Reduce task size or frequency |
| Need more capacity | Increase `max_vcpus` |

### Getting Help

1. Check logs: `aws logs tail [log-group] --follow`
2. Check job status: `aws batch describe-jobs --jobs [job-id]`
3. Review AWS Console: Batch > Jobs

---

**Ready to migrate?** Start with Step 1 above and deploy in ~15 minutes! 🚀

For questions or issues, review the troubleshooting section or check the Terraform outputs for useful commands.

