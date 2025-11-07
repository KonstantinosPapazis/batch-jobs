# Using Existing ECS Cluster for Scheduled Jobs

If you already have an ECS cluster and want to run scheduled batch jobs on it **without AWS Batch**, you can use **ECS Scheduled Tasks** with EventBridge.

## 🆚 AWS Batch vs ECS Scheduled Tasks

| Feature | AWS Batch | ECS Scheduled Tasks |
|---------|-----------|---------------------|
| **Use Existing Cluster** | ❌ No (creates own) | ✅ Yes |
| **Auto-scaling** | ✅ Automatic | ⚠️ Manual |
| **Job Queue** | ✅ Built-in | ❌ None |
| **Retry Logic** | ✅ Built-in | ⚠️ Manual |
| **Priority** | ✅ Yes | ❌ No |
| **Dependencies** | ✅ Yes | ❌ No |
| **Best For** | Complex batch workflows | Simple scheduled tasks |

## 🚀 Quick Setup: ECS Scheduled Tasks

### Prerequisites
- Existing ECS cluster (Fargate or EC2)
- Task definition already created
- EventBridge permissions

### Terraform Example

```hcl
# Reference your existing ECS cluster
data "aws_ecs_cluster" "existing" {
  cluster_name = "my-existing-cluster"
}

# Reference your existing task definition
data "aws_ecs_task_definition" "batch_job" {
  task_definition = "my-batch-job-task"
}

# Create EventBridge rule for scheduling
resource "aws_cloudwatch_event_rule" "scheduled_task" {
  name                = "daily-batch-job"
  description         = "Run batch job daily at 2 AM"
  schedule_expression = "cron(0 2 * * ? *)"
}

# IAM role for EventBridge to run ECS tasks
resource "aws_iam_role" "eventbridge_ecs" {
  name = "eventbridge-ecs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_ecs" {
  name = "eventbridge-ecs-policy"
  role = aws_iam_role.eventbridge_ecs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecs:RunTask"
      ]
      Resource = data.aws_ecs_task_definition.batch_job.arn
    },
    {
      Effect = "Allow"
      Action = [
        "iam:PassRole"
      ]
      Resource = "*"
      Condition = {
        StringLike = {
          "iam:PassedToService": "ecs-tasks.amazonaws.com"
        }
      }
    }]
  })
}

# EventBridge target to run ECS task
resource "aws_cloudwatch_event_target" "ecs_scheduled_task" {
  rule     = aws_cloudwatch_event_rule.scheduled_task.name
  arn      = data.aws_ecs_cluster.existing.arn
  role_arn = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = data.aws_ecs_task_definition.batch_job.arn
    launch_type         = "FARGATE"  # or "EC2"
    
    network_configuration {
      subnets          = ["subnet-xxx", "subnet-yyy"]
      security_groups  = ["sg-xxx"]
      assign_public_ip = false
    }

    # Optional: Platform version for Fargate
    platform_version = "LATEST"
  }
}
```

### AWS CLI Example

```bash
# Create EventBridge rule
aws events put-rule \
  --name daily-batch-job \
  --schedule-expression "cron(0 2 * * ? *)"

# Add ECS task as target
aws events put-targets \
  --rule daily-batch-job \
  --targets '[
    {
      "Id": "1",
      "Arn": "arn:aws:ecs:us-east-1:123456789012:cluster/my-existing-cluster",
      "RoleArn": "arn:aws:iam::123456789012:role/ecsEventsRole",
      "EcsParameters": {
        "TaskDefinitionArn": "arn:aws:ecs:us-east-1:123456789012:task-definition/my-batch-job:1",
        "TaskCount": 1,
        "LaunchType": "FARGATE",
        "NetworkConfiguration": {
          "awsvpcConfiguration": {
            "Subnets": ["subnet-xxx"],
            "SecurityGroups": ["sg-xxx"],
            "AssignPublicIp": "DISABLED"
          }
        }
      }
    }
  ]'
```

## ⚠️ Limitations of ECS Scheduled Tasks

1. **No Job Queue**: Tasks run immediately or fail (no queuing)
2. **No Retries**: Must implement retry logic in your code
3. **No Priorities**: All tasks treated equally
4. **No Dependencies**: Can't chain tasks easily
5. **Manual Scaling**: Cluster must have capacity

## 💡 When to Use Each Approach

### Use **ECS Scheduled Tasks** if:
- ✅ You already have an ECS cluster
- ✅ Simple scheduled tasks (no complex workflows)
- ✅ Don't need queuing or priorities
- ✅ Want to minimize infrastructure

### Use **AWS Batch** if:
- ✅ Need job queuing and priorities
- ✅ Complex workflows with dependencies
- ✅ Built-in retry logic required
- ✅ Auto-scaling is important
- ✅ Don't have existing ECS cluster

## 🔄 Hybrid Approach

You can have **both** running:
- Regular services on your ECS cluster
- AWS Batch for complex batch jobs (creates separate cluster)
- They don't interfere with each other!

```
Your Infrastructure:
├── ECS Cluster (existing)
│   ├── Web services
│   ├── APIs
│   └── Scheduled tasks (simple)
│
└── AWS Batch (separate)
    └── Complex batch jobs with queuing
```

## 📚 Additional Resources

- [ECS Scheduled Tasks Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/scheduled_tasks.html)
- [EventBridge with ECS](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-ecs-tutorial.html)

