# AWS Batch Architecture

## 📐 System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                         VPC                                 │ │
│  │                                                             │ │
│  │  ┌──────────────────┐         ┌──────────────────┐        │ │
│  │  │  Public Subnet   │         │  Public Subnet   │        │ │
│  │  │   (us-east-1a)   │         │   (us-east-1b)   │        │ │
│  │  │                  │         │                  │        │ │
│  │  │  ┌───────────┐   │         │                  │        │ │
│  │  │  │    NAT    │   │         │                  │        │ │
│  │  │  │  Gateway  │   │         │                  │        │ │
│  │  │  └─────┬─────┘   │         │                  │        │ │
│  │  └────────┼─────────┘         └──────────────────┘        │ │
│  │           │                                                 │ │
│  │  ┌────────┼──────────────────┬──────────────────┐         │ │
│  │  │        │                  │                  │         │ │
│  │  │  ┌─────▼──────┐    ┌──────▼──────┐          │         │ │
│  │  │  │  Private   │    │  Private    │          │         │ │
│  │  │  │  Subnet    │    │  Subnet     │          │         │ │
│  │  │  │(us-east-1a)│    │(us-east-1b) │          │         │ │
│  │  │  │            │    │             │          │         │ │
│  │  │  │  ┌──────┐  │    │  ┌──────┐   │          │         │ │
│  │  │  │  │ EC2  │  │    │  │ EC2  │   │          │         │ │
│  │  │  │  │Batch │  │    │  │Batch │   │          │         │ │
│  │  │  │  │Instance│ │    │  │Instance│  │         │         │ │
│  │  │  │  └──────┘  │    │  └──────┘   │          │         │ │
│  │  │  │            │    │             │          │         │ │
│  │  │  └────────────┘    └─────────────┘          │         │ │
│  │  │                                              │         │ │
│  │  │         AWS Batch Compute Environment       │         │ │
│  │  └──────────────────────────────────────────────┘         │ │
│  │                                                             │ │
│  │  ┌──────────────────────────────────────────────┐         │ │
│  │  │        VPC Endpoints (Optional)              │         │ │
│  │  │  • S3 Gateway Endpoint                       │         │ │
│  │  │  • ECR API Interface Endpoint                │         │ │
│  │  │  • ECR Docker Interface Endpoint             │         │ │
│  │  │  • CloudWatch Logs Interface Endpoint        │         │ │
│  │  └──────────────────────────────────────────────┘         │ │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐      │
│  │  EventBridge │   │  AWS Batch   │   │     ECR      │      │
│  │   (Cron)     │──▶│  Job Queue   │──▶│  Repository  │      │
│  └──────────────┘   └──────────────┘   └──────────────┘      │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐      │
│  │  CloudWatch  │   │   Secrets    │   │      S3      │      │
│  │     Logs     │   │   Manager    │   │   Buckets    │      │
│  └──────────────┘   └──────────────┘   └──────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 🏗️ Component Details

### 1. Networking Layer

#### VPC Configuration
- **CIDR Block:** 10.0.0.0/16
- **Availability Zones:** 2 (for high availability)
- **Subnets:**
  - **Public Subnets:** 10.0.1.0/24, 10.0.2.0/24
    - Used for NAT Gateway
    - Internet-facing resources
  - **Private Subnets:** 10.0.10.0/24, 10.0.20.0/24
    - Batch compute instances run here
    - No direct internet access (security)

#### Internet Gateway
- Provides internet access for public subnets
- Required for NAT Gateway

#### NAT Gateway (Optional)
- **Location:** Public subnet
- **Purpose:** Allows private subnet resources to access internet
- **Cost:** ~$32/month + data processing charges
- **Alternative:** VPC Endpoints (recommended for cost savings)

#### VPC Endpoints (Recommended)
- **S3 Gateway Endpoint:** Free, enables S3 access without NAT
- **ECR Interface Endpoints:** ~$7/month each for API and Docker
- **CloudWatch Logs Endpoint:** ~$7/month
- **Total Cost:** ~$21/month vs. $32+ for NAT Gateway
- **Benefit:** Reduced latency, no NAT data charges

### 2. AWS Batch Components

#### Compute Environment
```
Type: MANAGED
Compute Resources:
  - Type: EC2 (or FARGATE)
  - Min vCPUs: 0 (scale to zero)
  - Max vCPUs: 256
  - Instance Types: optimal (AWS chooses best)
  - Allocation: SPOT_CAPACITY_OPTIMIZED
  - Subnets: Private subnets
  - Security Group: batch-compute-sg
```

**Key Features:**
- **Auto-scaling:** Automatically scales based on job queue
- **Spot Instances:** 60-70% cost savings
- **Multi-AZ:** Distributed across availability zones

#### Job Queue
```
Name: batch-jobs-prod-job-queue
Priority: 1
State: ENABLED
Compute Environments:
  - batch-jobs-prod-compute-env (Order: 1)
```

**Behavior:**
- Jobs submitted to queue are scheduled on compute environment
- FIFO order with priority support
- Automatic retry on failure

#### Job Definitions
```
Type: container
Platform: EC2 (or FARGATE)
Resources:
  - vCPU: 1-8
  - Memory: 2048-16384 MB
Retry Strategy:
  - Attempts: 3
  - Evaluate on exit codes
Timeout: 1-4 hours
```

### 3. Container Registry (ECR)

#### Repository Configuration
```
Name: batch-jobs-prod
Image Scanning: Enabled
Encryption: AES256
Lifecycle Policy:
  - Keep last 10 tagged images
  - Remove untagged after 7 days
```

**Features:**
- **Automatic scanning:** Detects vulnerabilities
- **Lifecycle policies:** Automatic cleanup
- **Encrypted storage:** Security best practice

### 4. Scheduling & Orchestration

#### EventBridge (CloudWatch Events)
```
Type: Schedule
Expression: cron(0 2 * * ? *)  # Daily at 2 AM UTC
Target:
  - AWS Batch Job Queue
  - Job Definition
```

**Common Schedules:**
- Daily: `cron(0 2 * * ? *)`
- Twice daily: `cron(0 2,14 * * ? *)`
- Hourly: `rate(1 hour)`
- Weekly: `cron(0 2 ? * MON *)`

### 5. IAM Roles & Permissions

#### Role Hierarchy
```
1. Batch Service Role
   └─ Permissions: Manage compute environment

2. ECS Instance Role
   └─ Permissions: Pull images, write logs
   
3. Spot Fleet Role (if using Spot)
   └─ Permissions: Manage spot instances

4. Batch Execution Role
   └─ Permissions: Pull ECR images, create logs

5. Batch Job Role
   └─ Permissions: S3, Secrets Manager, CloudWatch
```

### 6. Monitoring & Logging

#### CloudWatch Logs
```
Log Group: /aws/batch/batch-jobs-prod
Retention: 30 days
Encryption: Enabled
```

**Log Streams:**
- One per job execution
- Includes stdout/stderr
- Real-time streaming available

#### CloudWatch Metrics
```
Namespace: AWS/Batch
Metrics:
  - SubmittedJobs
  - RunningJobs
  - SucceededJobs
  - FailedJobs
  - CPUUtilization
  - MemoryUtilization
```

#### CloudWatch Alarms
- Job failures
- Long-running jobs
- Queue depth
- Compute environment health

## 🔄 Job Execution Flow

### Standard Job Flow

```
1. Job Submission
   ├─ Via EventBridge (scheduled)
   ├─ Via AWS CLI/SDK (manual)
   └─ Via API Gateway (external trigger)
   
2. Job Queue
   ├─ Job enters SUBMITTED state
   ├─ Moves to PENDING
   └─ Becomes RUNNABLE when dependencies met
   
3. Compute Environment
   ├─ Checks available capacity
   ├─ Provisions EC2 instances if needed
   └─ Job moves to STARTING
   
4. Container Launch
   ├─ Pull image from ECR
   ├─ Inject environment variables
   ├─ Mount volumes (if any)
   └─ Job moves to RUNNING
   
5. Execution
   ├─ Container runs application
   ├─ Logs stream to CloudWatch
   └─ Metrics published
   
6. Completion
   ├─ Container exits (success or failure)
   ├─ Job moves to SUCCEEDED or FAILED
   ├─ Retry if needed (based on retry strategy)
   └─ Compute resources released
```

### Job States

```
SUBMITTED → PENDING → RUNNABLE → STARTING → RUNNING → SUCCEEDED
                                                     └─→ FAILED
```

**State Descriptions:**
- **SUBMITTED:** Job received by Batch
- **PENDING:** Waiting for dependencies
- **RUNNABLE:** Ready to run, waiting for compute
- **STARTING:** Container is starting
- **RUNNING:** Job is executing
- **SUCCEEDED:** Job completed successfully (exit code 0)
- **FAILED:** Job failed (non-zero exit code or error)

## 💰 Cost Optimization Architecture

### Optimized Configuration

```
┌─────────────────────────────────────────────────────────────┐
│                     Cost Optimization                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Spot Instances (60-70% savings)                         │
│     └─ Bid percentage: 80%                                  │
│                                                              │
│  2. Scale to Zero                                           │
│     └─ Min vCPUs: 0 (no idle costs)                         │
│                                                              │
│  3. VPC Endpoints (vs NAT Gateway)                          │
│     └─ Save ~$15-20/month                                   │
│                                                              │
│  4. Right-Sized Resources                                   │
│     └─ Monitor and adjust vCPU/memory                       │
│                                                              │
│  5. Log Retention Policies                                  │
│     └─ 30 days retention (vs. infinite)                     │
│                                                              │
│  6. ECR Lifecycle Policies                                  │
│     └─ Auto-cleanup old images                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘

Estimated Monthly Savings: $350-400 vs. on-premise
Annual Savings: $4,200-4,800
```

## 🔒 Security Architecture

### Security Layers

```
┌──────────────────────────────────────────────────────────┐
│                    Security Layers                        │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  1. Network Security                                      │
│     • Private subnets for compute instances              │
│     • Security groups with minimal permissions           │
│     • No direct internet access                          │
│     • VPC endpoints for AWS services                     │
│                                                           │
│  2. IAM Security                                          │
│     • Least privilege principle                          │
│     • Role-based access control                          │
│     • Separate roles for different functions             │
│     • No long-term credentials in containers             │
│                                                           │
│  3. Data Security                                         │
│     • Encrypted ECR images (AES256)                      │
│     • Encrypted CloudWatch logs                          │
│     • Secrets Manager for sensitive data                 │
│     • S3 encryption at rest                              │
│                                                           │
│  4. Container Security                                    │
│     • Non-root user in containers                        │
│     • Image scanning enabled                             │
│     • Minimal base images                                │
│     • Regular security updates                           │
│                                                           │
│  5. Monitoring & Compliance                               │
│     • CloudTrail for API logging                         │
│     • CloudWatch for metrics and logs                    │
│     • AWS Config for compliance                          │
│     • Automated vulnerability scanning                   │
│                                                           │
└──────────────────────────────────────────────────────────┘
```

## 📊 Scalability Architecture

### Auto-Scaling Behavior

```
Job Queue Depth    Compute Environment Response
─────────────────  ────────────────────────────
0 jobs             └─ Scale to 0 vCPUs (save costs)
                   
1-10 jobs          └─ Launch instances as needed
                      (optimal instance selection)
                   
10-50 jobs         └─ Scale up to max vCPUs
                      (parallel execution)
                   
50+ jobs           └─ Queue jobs until capacity available
                      (FIFO order with priority)
```

**Scaling Metrics:**
- **Scale-up time:** ~2-5 minutes (EC2 launch)
- **Scale-down time:** Immediate after job completion
- **Max capacity:** 256 vCPUs (configurable)
- **Concurrent jobs:** Limited by vCPU availability

## 🔧 High Availability Architecture

### HA Features

```
1. Multi-AZ Deployment
   ├─ Compute environment spans 2 AZs
   ├─ Automatic failover to healthy AZ
   └─ No single point of failure

2. Automatic Retry
   ├─ Retry on EC2 instance failures
   ├─ Retry on transient errors
   └─ Configurable retry attempts (3 default)

3. Managed Service Benefits
   ├─ AWS manages infrastructure
   ├─ Automatic patching and updates
   └─ Built-in health monitoring

4. Job Queue Durability
   ├─ Jobs persist across failures
   ├─ State maintained by AWS Batch
   └─ No job loss on infrastructure failure
```

## 🚀 Deployment Patterns

### Blue-Green Deployment

```
Phase 1: Deploy New Infrastructure (Green)
├─ Create new job definition version
├─ Test with single job
└─ Validate results

Phase 2: Gradual Migration
├─ Route 10% traffic to new version
├─ Monitor for issues
├─ Increase to 50%, then 100%
└─ Keep old version ready for rollback

Phase 3: Cleanup
├─ Deregister old job definition
└─ Remove old infrastructure
```

### Canary Deployment

```
Step 1: Deploy canary (5% traffic)
Step 2: Monitor metrics for 24 hours
Step 3: If healthy, deploy to 50%
Step 4: Monitor for another 24 hours
Step 5: Full deployment (100%)
```

## 📈 Monitoring Dashboard

### Key Metrics to Monitor

```
1. Job Metrics
   • Job submission rate
   • Job success rate
   • Job failure rate
   • Average job duration
   • Job queue depth

2. Compute Metrics
   • vCPU utilization
   • Memory utilization
   • Instance launch time
   • Spot interruption rate

3. Cost Metrics
   • Daily compute costs
   • Storage costs
   • Data transfer costs
   • Total monthly spend

4. Performance Metrics
   • Time in queue (RUNNABLE → STARTING)
   • Container launch time (STARTING → RUNNING)
   • Execution time (RUNNING → SUCCEEDED/FAILED)
```

## 🔄 Disaster Recovery

### Backup Strategy

```
1. Infrastructure as Code
   ├─ Terraform/CloudFormation in Git
   ├─ Version controlled
   └─ Quick recreation possible

2. Container Images
   ├─ ECR replication (optional)
   ├─ Versioned tags
   └─ Backup to S3 (optional)

3. Data Backup
   ├─ S3 versioning enabled
   ├─ Cross-region replication (optional)
   └─ Regular snapshots

4. Configuration Backup
   ├─ Job definitions exported
   ├─ IAM policies documented
   └─ Network configuration saved
```

### Recovery Time Objectives (RTO)

- **Infrastructure:** 15-30 minutes (Terraform/CFN deploy)
- **Container images:** 5-10 minutes (pull from ECR)
- **Job execution:** 2-5 minutes (job submission to running)
- **Total RTO:** 30-45 minutes

### Recovery Point Objectives (RPO)

- **Infrastructure:** 0 (code in Git)
- **Container images:** 0 (in ECR)
- **Job data:** Depends on S3 sync frequency
- **Logs:** Real-time (CloudWatch)

---

**Document Version:** 1.0  
**Last Updated:** November 2025

