terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # IMPORTANT: Configure backend for production
  # Uncomment and configure for your environment
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "batch-jobs/datascience/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  #   
  #   # Optional: Use assume role for cross-account access
  #   # role_arn = "arn:aws:iam::ACCOUNT_ID:role/TerraformRole"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Team        = "DataScience"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "DataScience"
    }
  }
}

