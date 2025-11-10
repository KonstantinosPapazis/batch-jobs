# IAM Roles: Per-Job vs Per-Team Approach

## 🤔 The Question

**Should each batch job have its own IAM role, or should teams share roles?**

## 📊 Quick Comparison

| Approach | Roles Created | Best For | Complexity | Security |
|----------|---------------|----------|------------|----------|
| **Per-Team (Recommended)** | 2 × teams | 90% of use cases | Low | Good |
| **Per-Job** | 2 × jobs | High-security needs | High | Best |

## 🎯 Recommendation: Per-Team (Shared Roles)

For most organizations, **one role per team** is the better approach.

### Why Per-Team is Better:

1. **Easier Management**: 6 roles for 3 teams vs 20 roles for 10 jobs
2. **Consistency**: All team jobs have same permissions
3. **Simpler Updates**: Change once, affects all team jobs
4. **Team Isolation**: Each team can only access their resources
5. **Audit Simplicity**: Track by team, not individual jobs

### Real-World Example:

**Your company has:**
- 3 teams (Data Engineering, ML, Analytics)
- 15 batch jobs total

**Option A: Per-Team (Recommended)**
```
6 IAM roles:
├── data-engineering-execution-role (shared by 7 jobs)
├── data-engineering-job-role (shared by 7 jobs)
├── ml-execution-role (shared by 5 jobs)
├── ml-job-role (shared by 5 jobs)
├── analytics-execution-role (shared by 3 jobs)
└── analytics-job-role (shared by 3 jobs)

Management: Easy
Updates: Change 2 roles to update entire team
```

**Option B: Per-Job**
```
30 IAM roles:
├── etl-job-1-execution-role
├── etl-job-1-job-role
├── etl-job-2-execution-role
├── etl-job-2-job-role
... (26 more roles)
└── report-job-15-job-role

Management: Complex
Updates: Must update each role individually
```

## 🏗️ Implementation

### Current Setup (Per-Job)

Your current `terraform-fargate/iam.tf` creates individual roles. This works but doesn't scale well.

```hcl
# iam.tf - Creates roles for each job definition
resource "aws_iam_role" "batch_execution" {
  name = "${local.name_prefix}-batch-execution-role"
  # Used by ALL jobs - not ideal
}

resource "aws_iam_role" "batch_job" {
  name = "${local.name_prefix}-batch-job-role"
  # Used by ALL jobs - not team-scoped
}
```

### Recommended Setup (Per-Team with Module)

Use the IAM roles module I created:

```hcl
# Create shared roles for each team
module "data_engineering_roles" {
  source = "./modules/batch-iam-roles"

  team_name      = "data-engineering"
  project_name   = var.project_name
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Scope permissions to team
  s3_resources = [
    "arn:aws:s3:::data-lake-prod/*",
    "arn:aws:s3:::analytics-prod/*"
  ]
}

# Use in multiple job definitions
resource "aws_batch_job_definition" "etl_job" {
  container_properties = jsonencode({
    executionRoleArn = module.data_engineering_roles.execution_role_arn
    jobRoleArn       = module.data_engineering_roles.job_role_arn
  })
}

resource "aws_batch_job_definition" "transform_job" {
  container_properties = jsonencode({
    executionRoleArn = module.data_engineering_roles.execution_role_arn
    jobRoleArn       = module.data_engineering_roles.job_role_arn
  })
}
```

## 📋 Migration Steps

### Step 1: Create Module Directory Structure

Already done! You have:
```
terraform-fargate/
└── modules/
    └── batch-iam-roles/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── README.md
```

### Step 2: Use Example Configuration

Copy and customize `examples-using-module.tf`:

```bash
cd terraform-fargate

# Review the example
cat examples-using-module.tf

# Uncomment the entire file
# Customize for your teams
nano examples-using-module.tf
```

### Step 3: Plan the Change

```bash
terraform plan

# You'll see:
# - New: module.data_engineering_roles.aws_iam_role.execution
# - New: module.data_engineering_roles.aws_iam_role.job
# - Update: aws_batch_job_definition.* (role ARN changes)
```

### Step 4: Apply Gradually

**Option A: Blue-Green (Safest)**
```bash
# 1. Create new module roles
terraform apply -target=module.data_engineering_roles

# 2. Update one job definition to use new roles
terraform apply -target=aws_batch_job_definition.test_job

# 3. Test the job
aws batch submit-job --job-definition test_job ...

# 4. If successful, update remaining jobs
terraform apply
```

**Option B: All at Once (Faster)**
```bash
# Apply everything
terraform apply
# Test all jobs
```

### Step 5: Clean Up Old Roles

After confirming everything works:

```bash
# Remove old roles from iam.tf
# Then run:
terraform apply
```

## 🔐 Security Considerations

### Team Isolation Strategy

```
Secrets Manager Structure:
/batch-jobs/data-engineering/database-password
/batch-jobs/data-engineering/api-key
/batch-jobs/ml/model-api-key
/batch-jobs/ml/training-credentials
/batch-jobs/analytics/warehouse-password

S3 Bucket Structure:
s3://company-data-lake/data-engineering/*
s3://company-data-lake/ml/*
s3://company-data-lake/analytics/*

IAM Permissions:
- data-engineering role: access only /data-engineering/ paths
- ml role: access only /ml/ paths
- analytics role: access only /analytics/ paths
```

### When Per-Job Roles ARE Necessary

Use individual roles per job if:

1. **Compliance Requirements**
   - SOC 2 Type II requires job-level isolation
   - PCI-DSS requires separate roles
   - HIPAA requires strict access control

2. **Drastically Different Permissions**
   ```
   Job A: Needs S3, DynamoDB, SQS
   Job B: Needs only CloudWatch
   Job C: Needs RDS, Secrets Manager, Lambda
   ```
   If every job is this different, per-job roles make sense.

3. **High-Risk Operations**
   ```
   Job A: Deletes data (destructive)
   Job B: Only reads data (safe)
   ```
   Separate these with different roles.

4. **Temporary/Contractor Jobs**
   - Jobs built by external teams
   - Need strict audit trail
   - Will be removed soon

## 📈 Scaling Comparison

### Scenario: Company Growth Over 2 Years

**Year 1:**
- 3 teams
- 10 jobs

**Year 2:**
- 5 teams
- 50 jobs

**IAM Roles Count:**

| Time | Per-Team | Per-Job | Difference |
|------|----------|---------|------------|
| Year 1 | 6 roles (3 teams × 2) | 20 roles (10 jobs × 2) | +14 roles |
| Year 2 | 10 roles (5 teams × 2) | 100 roles (50 jobs × 2) | +90 roles |

**Management Time (estimated):**

| Task | Per-Team | Per-Job |
|------|----------|---------|
| Add S3 bucket access | 1 role update | 50 role updates |
| New Secrets Manager path | 1 role update | 50 role updates |
| Security audit | Review 10 roles | Review 100 roles |
| Compliance report | 5 team reports | 50 job reports |

## 🎯 Decision Matrix

Answer these questions:

1. **How many teams?** 
   - < 5 teams: Per-team ✅
   - > 10 teams: Still per-team ✅

2. **How many jobs?**
   - < 10 jobs: Either works
   - > 20 jobs: Per-team ✅✅

3. **Job permission similarity within team?**
   - Similar: Per-team ✅
   - All different: Per-job

4. **Compliance requirements?**
   - Standard: Per-team ✅
   - Strict (SOC2, PCI-DSS): Per-job

5. **Team structure?**
   - Organized by teams: Per-team ✅
   - Ad-hoc individual projects: Per-job

## 📚 Further Reading

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Least Privilege Principle](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#grant-least-privilege)
- [AWS Batch IAM Roles](https://docs.aws.amazon.com/batch/latest/userguide/IAM_policies.html)

## 🎁 Bonus: Hybrid Approach

You can use BOTH approaches:

```hcl
# Most teams use shared roles
module "data_engineering_roles" {
  source    = "./modules/batch-iam-roles"
  team_name = "data-engineering"
}

# But one high-security job gets its own role
resource "aws_iam_role" "sensitive_job_execution" {
  name = "sensitive-data-deletion-execution-role"
  # Highly restricted, audited separately
}
```

---

**Bottom Line**: For your use case with Fargate Batch, **use per-team roles** (the module approach). It will save you time, reduce complexity, and still maintain good security through team isolation.

Want me to help you implement this for your specific teams? 🚀

