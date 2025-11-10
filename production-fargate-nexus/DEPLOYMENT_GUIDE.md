# Deployment Guide - Production AWS Batch with Fargate

## 🎯 Overview

This guide walks you through deploying your data science team's cron jobs to AWS Batch with Fargate, pulling images from your Nexus registry.

**Time to deploy:** ~15 minutes

## 📋 Prerequisites

### 1. Required Tools

```bash
# Check if installed
terraform --version  # >= 1.0
aws --version        # >= 2.0
```

If not installed:
- [Terraform Installation](https://www.terraform.io/downloads)
- [AWS CLI Installation](https://aws.amazon.com/cli/)

### 2. AWS Access

```bash
# Configure AWS credentials
aws configure

# Verify access
aws sts get-caller-identity
```

### 3. Network Access to Nexus

**Important:** Your AWS VPC needs to reach your Nexus registry.

**If Nexus is on-premise:**
- ✅ Set up VPN connection to AWS
- ✅ Or use AWS Direct Connect
- ✅ Ensure firewall allows AWS VPC CIDR blocks

**Test connectivity:**
```bash
# From an EC2 instance in your VPC
telnet nexus.company.com 5000
```

## 🚀 Step-by-Step Deployment

### Step 1: Store Nexus Credentials

**Option A: Using the helper script (Recommended)**

```bash
cd production-fargate-nexus/scripts
chmod +x setup-nexus-secret.sh
./setup-nexus-secret.sh
```

Follow the prompts and note the ARN provided.

**Option B: Manual AWS CLI**

```bash
aws secretsmanager create-secret \
  --name batch-jobs/datascience/nexus-credentials \
  --description "Nexus credentials for data science batch jobs" \
  --secret-string '{
    "username": "your-nexus-username",
    "password": "your-nexus-password",
    "registry": "nexus.company.com:5000"
  }' \
  --region us-east-1
```

Save the returned ARN - you'll need it next.

### Step 2: Configure Terraform

```bash
cd production-fargate-nexus

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit configuration
nano terraform.tfvars
```

**Required changes:**

```hcl
# Update these values:
nexus_registry_url = "nexus.company.com:5000"                    # Your Nexus URL
nexus_secret_arn   = "arn:aws:secretsmanager:us-east-1:..."     # From Step 1
container_image    = "nexus.company.com:5000/datascience/job:latest"  # Your image

# Update alert email
alert_email = "datascience-team@company.com"

# Update S3 buckets your jobs need
s3_bucket_arns = [
  "arn:aws:s3:::your-data-bucket",
  "arn:aws:s3:::your-data-bucket/*"
]
```

### Step 3: Initialize Terraform

```bash
terraform init
```

This downloads required providers and modules.

### Step 4: Review Infrastructure Plan

```bash
terraform plan
```

**Review what will be created:**
- ✅ VPC with private subnets
- ✅ VPC endpoints (saves ~$30/month)
- ✅ AWS Batch compute environment
- ✅ Job queue and job definition
- ✅ IAM roles
- ✅ EventBridge rule (2 AM daily)
- ✅ CloudWatch logs and alarms

**Expected resources:** ~40 resources

### Step 5: Deploy!

```bash
terraform apply
```

Type `yes` when prompted.

**Deployment time:** 8-12 minutes

### Step 6: Verify Deployment

After successful deployment:

```bash
# Check if job queue is ready
aws batch describe-job-queues \
  --job-queues $(terraform output -raw job_queue_name)

# Check EventBridge rule
aws events describe-rule \
  --name $(terraform output -raw eventbridge_rule_name)
```

### Step 7: Test Manual Job Submission

**Before waiting for 2 AM, test manually:**

```bash
# Submit test job
aws batch submit-job \
  --job-name "manual-test-$(date +%s)" \
  --job-queue $(terraform output -raw job_queue_name) \
  --job-definition $(terraform output -raw job_definition_name)

# Note the job ID from output
JOB_ID="abc-123-xyz"

# Watch job progress
watch -n 10 "aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].status'"
```

### Step 8: Monitor Logs

```bash
# Tail logs in real-time
aws logs tail $(terraform output -raw log_group_name) --follow

# Or view in AWS Console:
# CloudWatch > Log Groups > /aws/batch/batch-jobs-datascience-prod
```

### Step 9: Verify Email Alerts

If you configured `alert_email`:
1. Check your email for SNS subscription confirmation
2. Click "Confirm subscription"
3. You'll receive alerts when jobs fail

## 🎉 Success Checklist

After deployment, verify:

- ✅ Terraform apply completed successfully
- ✅ Manual test job succeeded
- ✅ Logs appear in CloudWatch
- ✅ EventBridge rule is enabled
- ✅ Email subscription confirmed
- ✅ Job outputs are as expected

## 📅 What Happens Next

Your job will now run:
- **Daily at 2 AM UTC** (convert to your timezone)
- **Automatically retries** 2 times on failure
- **Logs to CloudWatch** (30-day retention)
- **Sends alerts** on failures (if email configured)
- **Scales to zero** when not running (no idle costs)

## 🔧 Common Tasks

### Change Schedule

Edit `terraform.tfvars`:
```hcl
schedule_expression = "cron(0 14 * * ? *)"  # Change to 2 PM UTC
```

```bash
terraform apply
```

### Disable Schedule Temporarily

```bash
# Disable
aws events disable-rule --name $(terraform output -raw eventbridge_rule_name)

# Re-enable
aws events enable-rule --name $(terraform output -raw eventbridge_rule_name)
```

### Update Container Image

If using `:latest` tag, no changes needed - Batch pulls latest on each run.

If using version tags:
```hcl
# In terraform.tfvars
container_image = "nexus.company.com:5000/datascience/job:v2.0.0"
```

```bash
terraform apply
```

### Adjust Resources

If jobs need more CPU/memory:
```hcl
# In terraform.tfvars
task_vcpu   = "0.5"   # Increase from 0.25
task_memory = "1024"  # Increase from 512
```

```bash
terraform apply
```

### View Recent Jobs

```bash
aws batch list-jobs \
  --job-queue $(terraform output -raw job_queue_name) \
  --job-status SUCCEEDED \
  --max-items 10
```

## 🐛 Troubleshooting

### Job Fails: "CannotPullContainerError"

**Cause:** Can't connect to Nexus or wrong credentials

**Solutions:**
1. Verify Nexus credentials:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id $(terraform output -raw nexus_secret_arn)
   ```

2. Check VPN/Direct Connect to Nexus

3. Verify image path in terraform.tfvars

### Job Stuck in RUNNABLE

**Cause:** No compute capacity

**Solution:**
```hcl
# Increase in terraform.tfvars
max_vcpus = 512
```

```bash
terraform apply
```

### Job Fails Immediately

**Check logs:**
```bash
aws logs tail $(terraform output -raw log_group_name) --since 1h
```

Look for error messages from your application.

### No Logs Appearing

**Verify CloudWatch log group:**
```bash
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/batch/batch-jobs"
```

### Email Alerts Not Working

1. Check SNS subscription:
   ```bash
   aws sns list-subscriptions-by-topic \
     --topic-arn $(terraform output -raw sns_topic_arn)
   ```

2. Confirm subscription in email

## 💰 Cost Monitoring

### View Current Costs

```bash
# AWS Console: Cost Explorer
# Filter by:
# - Tag: Team=datascience
# - Service: AWS Batch, VPC, CloudWatch
```

### Expected Monthly Cost

For 1 job/day, 30 min each:
- Fargate: $1.21
- VPC Endpoints: $21.00
- CloudWatch Logs: $2.50
- S3: $2.30
- **Total: ~$27/month**

## 🔄 Adding More Jobs

To add another cron job:

1. **Copy job definition in main.tf:**
   ```hcl
   resource "aws_batch_job_definition" "weekly_job" {
     name = "${local.name_prefix}-weekly-job"
     # ... similar config
   }
   ```

2. **Add EventBridge rule:**
   ```hcl
   resource "aws_cloudwatch_event_rule" "weekly_job" {
     schedule_expression = "cron(0 3 ? * MON *)"  # Monday 3 AM
   }
   ```

3. **Apply changes:**
   ```bash
   terraform apply
   ```

## 📚 Additional Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/)
- [EventBridge Schedule Expressions](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html)

## 🆘 Getting Help

1. **Check logs first:** `terraform output view_logs_command`
2. **Review job details:** `terraform output describe_job_command`
3. **Check EventBridge:** AWS Console > EventBridge > Rules
4. **Review alarms:** AWS Console > CloudWatch > Alarms

## 🧹 Cleanup (If Needed)

To remove all infrastructure:

```bash
terraform destroy
```

**⚠️ Warning:** This deletes everything and cannot be undone!

---

**Ready?** Start with Step 1 above! 🚀

