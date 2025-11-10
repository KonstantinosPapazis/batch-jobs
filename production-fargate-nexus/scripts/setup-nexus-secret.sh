#!/bin/bash
# =============================================================================
# Setup Nexus Credentials in AWS Secrets Manager
# =============================================================================
# This script creates the secret needed for AWS Batch to pull images from Nexus
# 
# Usage: ./setup-nexus-secret.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Nexus Credentials Setup${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Get configuration
read -p "AWS Region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

read -p "Secret name [batch-jobs/datascience/nexus-credentials]: " SECRET_NAME
SECRET_NAME=${SECRET_NAME:-batch-jobs/datascience/nexus-credentials}

echo ""
echo -e "${YELLOW}Enter Nexus Registry Details:${NC}"
read -p "Nexus Registry URL (e.g., nexus.company.com:5000): " NEXUS_URL
read -p "Nexus Username: " NEXUS_USERNAME
read -s -p "Nexus Password: " NEXUS_PASSWORD
echo ""

# Validate inputs
if [ -z "$NEXUS_URL" ] || [ -z "$NEXUS_USERNAME" ] || [ -z "$NEXUS_PASSWORD" ]; then
    echo -e "${RED}Error: All fields are required${NC}"
    exit 1
fi

# Create JSON secret
SECRET_JSON=$(cat <<EOF
{
  "username": "$NEXUS_USERNAME",
  "password": "$NEXUS_PASSWORD",
  "registry": "$NEXUS_URL"
}
EOF
)

echo ""
echo -e "${BLUE}Creating secret in AWS Secrets Manager...${NC}"

# Check if secret exists
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${YELLOW}Secret already exists. Updating...${NC}"
    
    SECRET_ARN=$(aws secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME" \
        --secret-string "$SECRET_JSON" \
        --region "$AWS_REGION" \
        --query 'ARN' \
        --output text)
else
    echo -e "${BLUE}Creating new secret...${NC}"
    
    SECRET_ARN=$(aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Nexus registry credentials for Data Science team batch jobs" \
        --secret-string "$SECRET_JSON" \
        --region "$AWS_REGION" \
        --query 'ARN' \
        --output text)
fi

echo ""
echo -e "${GREEN}✓ Success!${NC}"
echo ""
echo -e "${BLUE}Secret Details:${NC}"
echo "  Name:   $SECRET_NAME"
echo "  ARN:    $SECRET_ARN"
echo "  Region: $AWS_REGION"
echo ""
echo -e "${YELLOW}IMPORTANT: Add this ARN to your terraform.tfvars:${NC}"
echo ""
echo "nexus_secret_arn = \"$SECRET_ARN\""
echo ""
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Update terraform.tfvars with the ARN above"
echo "2. Verify Nexus registry URL matches: $NEXUS_URL"
echo "3. Run: terraform plan"
echo ""

