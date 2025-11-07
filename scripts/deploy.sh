#!/bin/bash
# =============================================================================
# AWS Batch Deployment Script
# =============================================================================
# This script helps deploy the AWS Batch infrastructure and Docker images
#
# Usage:
#   ./deploy.sh [terraform|cloudformation] [options]
#
# Examples:
#   ./deploy.sh terraform          # Deploy using Terraform
#   ./deploy.sh cloudformation     # Deploy using CloudFormation
#   ./deploy.sh build-push         # Build and push Docker image only
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
PROJECT_NAME="${PROJECT_NAME:-batch-jobs}"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_deps=()
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_deps+=("aws-cli")
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    # Check Terraform (if needed)
    if [[ "$1" == "terraform" ]] && ! command -v terraform &> /dev/null; then
        missing_deps+=("terraform")
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found (optional but recommended)"
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo -e "\nPlease install the missing dependencies:"
        echo "  - AWS CLI: https://aws.amazon.com/cli/"
        echo "  - Docker: https://docs.docker.com/get-docker/"
        echo "  - Terraform: https://www.terraform.io/downloads"
        exit 1
    fi
    
    print_success "All prerequisites installed"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        echo "Run: aws configure"
        exit 1
    fi
    
    local aws_account=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS credentials configured (Account: $aws_account)"
}

deploy_terraform() {
    print_header "Deploying with Terraform"
    
    cd "$PROJECT_ROOT/terraform"
    
    # Check if terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        print_warning "terraform.tfvars not found"
        print_info "Creating from example file..."
        cp terraform.tfvars.example terraform.tfvars
        print_warning "Please edit terraform.tfvars with your values and run again"
        exit 1
    fi
    
    # Initialize Terraform
    print_info "Initializing Terraform..."
    terraform init
    
    # Validate configuration
    print_info "Validating Terraform configuration..."
    terraform validate
    
    # Plan
    print_info "Creating Terraform plan..."
    terraform plan -out=tfplan
    
    # Ask for confirmation
    echo -e "\n${YELLOW}Review the plan above. Do you want to apply? (yes/no)${NC}"
    read -r response
    
    if [[ "$response" != "yes" ]]; then
        print_warning "Deployment cancelled"
        rm tfplan
        exit 0
    fi
    
    # Apply
    print_info "Applying Terraform configuration..."
    terraform apply tfplan
    rm tfplan
    
    print_success "Terraform deployment completed!"
    
    # Output important values
    print_header "Deployment Outputs"
    terraform output
}

deploy_cloudformation() {
    print_header "Deploying with CloudFormation"
    
    cd "$PROJECT_ROOT/cloudformation"
    
    # Check if parameters file exists
    if [ ! -f "parameters.json" ]; then
        print_warning "parameters.json not found"
        print_info "Creating from example file..."
        cp parameters.example.json parameters.json
        print_warning "Please edit parameters.json with your values and run again"
        exit 1
    fi
    
    local stack_name="${PROJECT_NAME}-${ENVIRONMENT}-stack"
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null; then
        print_info "Stack exists, updating..."
        local operation="update-stack"
    else
        print_info "Creating new stack..."
        local operation="create-stack"
    fi
    
    # Deploy stack
    print_info "Deploying CloudFormation stack: $stack_name"
    aws cloudformation "$operation" \
        --stack-name "$stack_name" \
        --template-body file://batch-stack.yaml \
        --parameters file://parameters.json \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION"
    
    # Wait for completion
    print_info "Waiting for stack to complete..."
    if [[ "$operation" == "create-stack" ]]; then
        aws cloudformation wait stack-create-complete \
            --stack-name "$stack_name" \
            --region "$AWS_REGION"
    else
        aws cloudformation wait stack-update-complete \
            --stack-name "$stack_name" \
            --region "$AWS_REGION"
    fi
    
    print_success "CloudFormation deployment completed!"
    
    # Output stack outputs
    print_header "Stack Outputs"
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs' \
        --output table
}

build_and_push_image() {
    print_header "Building and Pushing Docker Image"
    
    # Get ECR repository URL
    local ecr_repo
    if [ -d "$PROJECT_ROOT/terraform" ] && [ -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
        cd "$PROJECT_ROOT/terraform"
        ecr_repo=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
    fi
    
    if [ -z "$ecr_repo" ]; then
        # Try CloudFormation
        local stack_name="${PROJECT_NAME}-${ENVIRONMENT}-stack"
        ecr_repo=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryUrl`].OutputValue' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$ecr_repo" ]; then
        print_error "Could not find ECR repository URL"
        print_info "Please ensure infrastructure is deployed first"
        exit 1
    fi
    
    print_info "ECR Repository: $ecr_repo"
    
    # Authenticate Docker to ECR
    print_info "Authenticating Docker to ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ecr_repo"
    
    # Build Docker image
    cd "$PROJECT_ROOT/examples/sample-job"
    
    local image_tag="${1:-latest}"
    print_info "Building Docker image with tag: $image_tag"
    docker build -t "$PROJECT_NAME:$image_tag" .
    
    # Tag for ECR
    print_info "Tagging image for ECR..."
    docker tag "$PROJECT_NAME:$image_tag" "$ecr_repo:$image_tag"
    
    # Also tag with version if not 'latest'
    if [ "$image_tag" != "latest" ]; then
        docker tag "$PROJECT_NAME:$image_tag" "$ecr_repo:latest"
    fi
    
    # Push to ECR
    print_info "Pushing image to ECR..."
    docker push "$ecr_repo:$image_tag"
    
    if [ "$image_tag" != "latest" ]; then
        docker push "$ecr_repo:latest"
    fi
    
    print_success "Docker image pushed to ECR: $ecr_repo:$image_tag"
}

test_deployment() {
    print_header "Testing Deployment"
    
    # Get job queue and definition names
    local job_queue job_definition
    
    if [ -d "$PROJECT_ROOT/terraform" ] && [ -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
        cd "$PROJECT_ROOT/terraform"
        job_queue=$(terraform output -raw batch_job_queue_name 2>/dev/null || echo "")
        job_definition=$(terraform output -raw example_job_definition_name 2>/dev/null || echo "")
    else
        local stack_name="${PROJECT_NAME}-${ENVIRONMENT}-stack"
        job_queue=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`BatchJobQueueName`].OutputValue' \
            --output text 2>/dev/null || echo "")
        
        job_definition="${PROJECT_NAME}-${ENVIRONMENT}-example-job"
    fi
    
    if [ -z "$job_queue" ] || [ -z "$job_definition" ]; then
        print_error "Could not find job queue or definition"
        exit 1
    fi
    
    print_info "Job Queue: $job_queue"
    print_info "Job Definition: $job_definition"
    
    # Submit test job
    print_info "Submitting test job..."
    local job_id=$(aws batch submit-job \
        --job-name "test-job-$(date +%Y%m%d-%H%M%S)" \
        --job-queue "$job_queue" \
        --job-definition "$job_definition" \
        --region "$AWS_REGION" \
        --query 'jobId' \
        --output text)
    
    print_success "Job submitted: $job_id"
    print_info "Monitor job status: aws batch describe-jobs --jobs $job_id --region $AWS_REGION"
    
    # Optional: Wait for job completion
    echo -e "\n${YELLOW}Wait for job completion? (yes/no)${NC}"
    read -r wait_response
    
    if [[ "$wait_response" == "yes" ]]; then
        print_info "Waiting for job to complete..."
        while true; do
            local status=$(aws batch describe-jobs \
                --jobs "$job_id" \
                --region "$AWS_REGION" \
                --query 'jobs[0].status' \
                --output text)
            
            echo -ne "\rJob status: $status    "
            
            if [[ "$status" == "SUCCEEDED" ]]; then
                echo ""
                print_success "Job completed successfully!"
                break
            elif [[ "$status" == "FAILED" ]]; then
                echo ""
                print_error "Job failed!"
                break
            fi
            
            sleep 10
        done
    fi
}

print_usage() {
    cat << EOF
Usage: $0 [command] [options]

Commands:
    terraform           Deploy infrastructure using Terraform
    cloudformation      Deploy infrastructure using CloudFormation
    build-push [tag]    Build and push Docker image (default tag: latest)
    test                Submit a test job
    full [method]       Full deployment (infrastructure + image + test)
    help                Show this help message

Environment Variables:
    AWS_REGION         AWS region (default: us-east-1)
    ENVIRONMENT        Environment name (default: prod)
    PROJECT_NAME       Project name (default: batch-jobs)

Examples:
    $0 terraform
    $0 cloudformation
    $0 build-push v1.0.0
    $0 test
    $0 full terraform

EOF
}

# =============================================================================
# Main Script
# =============================================================================

main() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 0
    fi
    
    case "$1" in
        terraform)
            check_prerequisites terraform
            deploy_terraform
            ;;
        cloudformation)
            check_prerequisites cloudformation
            deploy_cloudformation
            ;;
        build-push)
            check_prerequisites
            build_and_push_image "${2:-latest}"
            ;;
        test)
            check_prerequisites
            test_deployment
            ;;
        full)
            check_prerequisites "${2:-terraform}"
            if [ "${2:-terraform}" == "terraform" ]; then
                deploy_terraform
            else
                deploy_cloudformation
            fi
            build_and_push_image "latest"
            test_deployment
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            print_error "Unknown command: $1"
            print_usage
            exit 1
            ;;
    esac
    
    print_header "Deployment Complete! 🎉"
}

# Run main function
main "$@"

