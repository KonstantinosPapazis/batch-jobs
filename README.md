# AWS Batch Migration Project

This repository contains everything you need to migrate your on-premise Docker batch jobs to AWS Batch.

## 📁 Repository Structure

```
batch-jobs/
├── README.md                          # This file
├── docs/
│   ├── MIGRATION_GUIDE.md            # Step-by-step migration guide
│   ├── COST_COMPARISON.md            # Detailed cost analysis
│   └── ARCHITECTURE.md               # Architecture diagrams and explanations
├── terraform/                         # Terraform IaC (recommended)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── batch.tf
│   ├── networking.tf
│   ├── iam.tf
│   └── terraform.tfvars.example
├── cloudformation/                    # CloudFormation alternative
│   ├── batch-stack.yaml
│   └── parameters.example.json
├── examples/
│   ├── sample-job/                   # Example Docker batch job
│   │   ├── Dockerfile
│   │   ├── app.py
│   │   └── requirements.txt
│   └── job-definitions/              # AWS Batch job definition examples
│       ├── simple-job.json
│       └── gpu-job.json
├── scripts/
│   ├── deploy.sh                     # Deployment automation
│   ├── submit-job.sh                 # Job submission helper
│   └── cleanup.sh                    # Resource cleanup
└── cost-analysis/
    ├── cost-comparison.csv           # Cost comparison spreadsheet
    └── calculator.py                 # Cost estimation tool
```

## 🚀 Quick Start

### Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Terraform >= 1.0 (if using Terraform approach)
- Docker installed locally

### Option 1: Deploy with Terraform (Recommended)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

### Option 2: Deploy with CloudFormation

```bash
cd cloudformation
aws cloudformation create-stack \
  --stack-name batch-infrastructure \
  --template-body file://batch-stack.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

## 📊 What's Included

### 1. Infrastructure as Code
- **Terraform**: Modular, reusable infrastructure code
- **CloudFormation**: Native AWS template
- Both create:
  - VPC with public/private subnets
  - AWS Batch compute environment
  - Job queues
  - IAM roles and policies
  - ECR repository for Docker images
  - EventBridge rules for scheduling
  - CloudWatch log groups

### 2. Cost Comparison
- Detailed breakdown comparing:
  - Current on-premise Docker server costs
  - AWS Batch
  - AWS Step Functions
  - AWS MWAA (Managed Airflow)
  - Prefect Cloud
- Monthly and annual projections
- Break-even analysis

### 3. Migration Guide
- Step-by-step migration process
- Docker image preparation
- Testing strategies
- Rollback procedures
- Best practices

## 💰 Estimated Costs

For jobs running 1-2 times per day:

| Solution | Monthly Cost | Notes |
|----------|--------------|-------|
| **AWS Batch** | **$5-30** | Pay per job execution only |
| Step Functions | $15-50 | Good for orchestration |
| MWAA (Airflow) | $300-500 | Always-on infrastructure |
| Prefect Cloud | $50-200 | Requires agent hosting |

*See `docs/COST_COMPARISON.md` for detailed analysis*

## 📖 Documentation

- **[Migration Guide](docs/MIGRATION_GUIDE.md)**: Complete migration walkthrough
- **[Cost Comparison](docs/COST_COMPARISON.md)**: Detailed cost analysis
- **[Architecture](docs/ARCHITECTURE.md)**: System design and architecture

## 🔧 Example Usage

### Build and Push Docker Image

```bash
cd examples/sample-job
docker build -t my-batch-job .

# Push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
docker tag my-batch-job:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/my-batch-job:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/my-batch-job:latest
```

### Submit a Job

```bash
./scripts/submit-job.sh my-job-definition my-job-queue
```

## 🎯 Key Features

- ✅ **Cost Optimized**: Pay only for compute time used
- ✅ **Auto-scaling**: Automatically scales based on job requirements
- ✅ **Scheduled Execution**: EventBridge integration for cron-like scheduling
- ✅ **Monitoring**: CloudWatch logs and metrics
- ✅ **Security**: VPC isolation, IAM roles, encrypted storage
- ✅ **Multi-environment**: Easy dev/staging/prod separation

## 🔐 Security Considerations

- All resources deployed in private subnets
- ECR images scanned for vulnerabilities
- IAM roles follow least privilege principle
- CloudWatch logs encrypted at rest
- Secrets managed via AWS Secrets Manager

## 🧪 Testing

1. **Local Testing**: Test Docker containers locally first
2. **Dev Environment**: Deploy to dev environment for validation
3. **Staging**: Run parallel with on-premise for comparison
4. **Production**: Gradual migration with rollback plan

## 📞 Support

For questions or issues:
1. Review the [Migration Guide](docs/MIGRATION_GUIDE.md)
2. Check [Architecture Documentation](docs/ARCHITECTURE.md)
3. Review AWS Batch documentation

## 📝 License

This project is provided as-is for internal use.

---

**Next Steps**: Start with the [Migration Guide](docs/MIGRATION_GUIDE.md) to begin your migration journey.
